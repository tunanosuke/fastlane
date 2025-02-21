module Fastlane
  module Actions
    ARGS_MAP = {
      workspace: '-w',
      project: '-p',
      configuration: '-c',
      scheme: '-s',
      clean: '--clean',
      archive: '--archive',
      destination: '-d',
      embed: '-m',
      identity: '-i',
      sdk: '--sdk',
      ipa: '--ipa',
      xcconfig: '--xcconfig',
      xcargs: '--xcargs'
    }

    class IpaAction < Action

      def self.is_supported?(platform)
        platform == :ios
      end

      def self.run(params)
        # The args we will build with
        build_args = nil

        # The output directory of the IPA and dSYM
        absolute_dest_directory = nil

        # Used to get the final path of the IPA and dSYM
        if dest = params[:destination]
          absolute_dest_directory = File.expand_path(dest)
        end

        # Maps nice developer build parameters to Shenzhen args
        build_args = params_to_build_args(params)

        unless (params[:scheme] rescue nil)
          Helper.log.warn "You haven't specified a scheme. This might cause problems. If you can't see any output, please pass a `scheme`"
        end

        # If no dest directory given, default to current directory
        absolute_dest_directory ||= Dir.pwd

        if Helper.test?
          Actions.lane_context[SharedValues::IPA_OUTPUT_PATH] = File.join(absolute_dest_directory, 'test.ipa')
          Actions.lane_context[SharedValues::DSYM_OUTPUT_PATH] = File.join(absolute_dest_directory, 'test.app.dSYM.zip')
          return build_args
        end

        # Joins args into space delimited string
        build_args = build_args.join(' ')

        core_command = "krausefx-ipa build #{build_args} --verbose | xcpretty"
        command = "set -o pipefail && #{core_command}"
        Helper.log.debug command

        begin
          Actions.sh command

          # Finds absolute path of IPA and dSYM
          absolute_ipa_path = find_ipa_file(absolute_dest_directory)
          absolute_dsym_path = find_dsym_file(absolute_dest_directory)

          # Sets shared values to use after this action is performed
          Actions.lane_context[SharedValues::IPA_OUTPUT_PATH] = absolute_ipa_path
          Actions.lane_context[SharedValues::DSYM_OUTPUT_PATH] = absolute_dsym_path
          ENV[SharedValues::IPA_OUTPUT_PATH.to_s] = absolute_ipa_path # for deliver
          ENV[SharedValues::DSYM_OUTPUT_PATH.to_s] = absolute_dsym_path
        rescue => ex
          [
            "-------------------------------------------------------",
            "Original Error:",
            " => " + ex.to_s,
            "A build error occured. This can have many reasons, usually",
            "it has something to do with code signing. The `ipa` action",
            "uses `shenzhen` under the hood: https://github.com/nomad/shenzhen",
            "For code signing related issues, check out this guide:",
            "https://github.com/KrauseFx/fastlane/blob/master/docs/CodeSigning.md",
            "The command that was used by fastlane:",
            core_command,
            "-------------------------------------------------------"
          ].each do |txt|
            Helper.log.error txt.yellow
          end

          # Raise a custom exception, as the the normal one is useless for the user
          raise "A build error occured, this is usually related to code signing. Take a look at the error above".red
        end
      end

      def self.params_to_build_args(config)
        params = config.values

        params = params.delete_if { |k, v| v.nil? }
        params = fill_in_default_values(params)

        # Maps nice developer param names to Shenzhen's `ipa build` arguments
        params.collect do |k, v|
          v ||= ''
          if args = ARGS_MAP[k]
            if k == :clean
              v == true ? '--clean' : '--no-clean'
            elsif k == :archive
              v == true ? '--archive' : '--no-archive'
            else
              value = (v.to_s.length > 0 ? "\"#{v}\"" : '')
              "#{ARGS_MAP[k]} #{value}".strip
            end
          end
        end.compact
      end

      def self.fill_in_default_values(params)
        embed = Actions.lane_context[Actions::SharedValues::SIGH_PROFILE_PATH] || ENV["SIGH_PROFILE_PATH"]
        params[:embed] ||= embed if embed
        params
      end

      def self.find_ipa_file(dir)
        # Finds last modified .ipa in the destination directory
        Dir[File.join(dir, '*.ipa')].sort { |a, b| File.mtime(b) <=> File.mtime(a) }.first
      end

      def self.find_dsym_file(dir)
        # Finds last modified .dSYM.zip in the destination directory
        Dir[File.join(dir, '*.dSYM.zip')].sort { |a, b| File.mtime(b) <=> File.mtime(a) }.first
      end

      def self.description
        "Easily build and sign your app using shenzhen"
      end

      def self.details
        [
          "More information on the shenzhen project page: https://github.com/nomad/shenzhen",
          "To make code signing work, it is recommended to set a the provisioning profile in the project settings."
        ].join(' ')
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :workspace,
                                       env_name: "IPA_WORKSPACE",
                                       description: "WORKSPACE Workspace (.xcworkspace) file to use to build app (automatically detected in current directory)",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :project,
                                       env_name: "IPA_PROJECT",
                                       description: "Project (.xcodeproj) file to use to build app (automatically detected in current directory, overridden by --workspace option, if passed)",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :configuration,
                                       env_name: "IPA_CONFIGURATION",
                                       description: "Configuration used to build",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :scheme,
                                       env_name: "IPA_SCHEME",
                                       description: "Scheme used to build app",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :clean,
                                       env_name: "IPA_CLEAN",
                                       description: "Clean project before building",
                                       optional: true,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :archive,
                                       env_name: "IPA_ARCHIVE",
                                       description: "Archive project after building",
                                       optional: true,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :destination,
                                       env_name: "IPA_DESTINATION",
                                       description: "Build destination. Defaults to current directory",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :embed,
                                       env_name: "IPA_EMBED",
                                       description: "Sign .ipa file with .mobileprovision",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :identity,
                                       env_name: "IPA_IDENTITY",
                                       description: "Identity to be used along with --embed",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :sdk,
                                       env_name: "IPA_SDK",
                                       description: "Use SDK as the name or path of the base SDK when building the project",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :ipa,
                                       env_name: "IPA_IPA",
                                       description: "Specify the name of the .ipa file to generate (including file extension)",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :xcconfig,
                                       env_name: "IPA_XCCONFIG",
                                       description: "Use an extra XCCONFIG file to build the app",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :xcargs,
                                       env_name: "IPA_XCARGS",
                                       description: "Pass additional arguments to xcodebuild when building the app. Be sure to quote multiple args",
                                       optional: true),
        ]
      end

      def self.output
        [
          ['IPA_OUTPUT_PATH', 'The path to the newly generated ipa file'],
          ['DSYM_OUTPUT_PATH', 'The path to the dsym file']
        ]
      end

      def self.author
        "joshdholtz"
      end
    end
  end
end
