require "itamae"

module Itamae
  module Plugin
    module Resource
      class Cron < ::Itamae::Resource::Base
        class Error < StandardError; end

        define_attribute :action, default: :create
        define_attribute :minute, type: String, default: '*'
        define_attribute :hour, type: String, default: '*'
        define_attribute :day, type: String, default: '*'
        define_attribute :month, type: String, default: '*'
        define_attribute :weekday, type: String, default: '*'
        define_attribute :cron_user, type: String, default: 'root'
        define_attribute :cron_name, type: String, default_name: true
        define_attribute :command, type: String
        define_attribute :owner, type: String, default: 'root'
        define_attribute :group, type: String, default: 'root'

        def pre_action
          case @current_action
          when :create
            attributes.exist = true
          when :delete
            attributes.exist = false
          end
        end

        def set_current_attributes
          if run_specinfra(:check_file_is_file, cron_file)
            current.exist = true

            fields = parse_crontab(backend.receive_file(cron_file))
            current.minute = fields[:minute]
            current.hour = fields[:hour]
            current.day = fields[:day]
            current.month = fields[:month]
            current.weekday = fields[:weekday]
            current.cron_user = fields[:cron_user]
            current.command = fields[:command]
            # current.owner = fields[:owner]
            # current.group = fields[:group]
          else
            current.exist = false
          end
        end

        def action_create(options)
          f = Tempfile.open('itamae')
          f.write(generate_cron)
          f.close

          temppath = ::File.join(runner.tmpdir, Time.now.to_f.to_s)
          backend.send_file(f.path, temppath)
          run_specinfra(:move_file, temppath, cron_file)
          run_specinfra(:change_file_owner, cron_file, attributes.owner, attributes.group)
        ensure
          f.unlink if f
        end

        def action_delete(options)
          if current.exist
            run_specinfra(:remove_file, cron_file)
          end
        end

        private

        def generate_cron
          <<-EOCRON
# DO NOT EDIT THIS MANUALLY
# BECAUSE THIS IS AUTO GENERATED BY Itamae
#{attributes.minute} #{attributes.hour} #{attributes.day} #{attributes.month} #{attributes.weekday} #{attributes.cron_user} #{attributes.command}
          EOCRON
        end

        def cron_file
          key = attributes.cron_name.gsub(%r{(\s+|/)}, '-')
          "/etc/cron.d/itamae-#{key}"
        end

        def parse_crontab(crontab)
          line = crontab.each_line.find {|l| !l.start_with?('#') }
          r = line.chomp.match(/\A([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+(.+)\z/)
          unless r
            raise Error, "Invalid crontab format."
          end

          {minute: r[1], hour: r[2], day: r[3], month: r[4], weekday: r[5],
           cron_user: r[6], command: r[7]}
        end
      end
    end
  end
end
