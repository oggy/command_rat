module CommandRat
  module RSpec
    module Matchers
      #
      # Matches if the given pattern appears in the next line of
      # standard output of the command.
      #
      #     app = CommandRat::Session.run('echo hi')
      #     app.should output('hi')
      #
      def output(pattern)
        Output.new(pattern)
      end

      #
      # Matches if the given pattern appears in the next line of
      # standard error of the command.
      #
      #     app = CommandRat::Session.run('myprog')
      #     app.should give_error('Eek!')
      #
      def give_error(pattern)
        Output.new(pattern, :stream => :stderr)
      end

      #
      # Matches if the command exited with the given status.
      #
      #     app = CommandRat::Session.run('echo')
      #     app.should have_exited_with(0)
      #
      def have_exited_with(status)
        HaveExitedWith.new(status)
      end

      # Abstract Matcher.
      class Matcher  #:nodoc:
        protected  # -------------------------------------------------

        def command_string(session)
          shelljoin(session.command)
        end

        private  # ---------------------------------------------------

        #
        # (Backport of ruby 1.9's Shellwords.shelljoin.)
        #
        def shelljoin(array)
          array.map { |arg| shellescape(arg) }.join(' ')
        end

        def shellescape(str)
          # An empty argument will be skipped, so return empty quotes.
          return "''" if str.empty?

          str = str.dup

          # Process as a single byte sequence because not all shell
          # implementations are multibyte aware.
          str.gsub!(/([^A-Za-z0-9_\-.,:\/@\n])/n, "\\\\\\1")

          # A LF cannot be escaped with a backslash because a backslash + LF
          # combo is regarded as line continuation and simply ignored.
          str.gsub!(/\n/, "'\n'")

          return str
        end
      end

      class Output < Matcher  #:nodoc:
        def initialize(pattern, options={})
          @pattern = pattern
          @stream = options[:stream] || :stdout
        end

        def matches?(session)
          @session = session
          !!session.consume_to(@pattern, :on => @stream)
        end

        def failure_message_for_should
          "next line of #{@stream} did not contain #{@pattern.inspect}"
        end

        def failure_message_for_should_not
          "next line of #{@stream} contained #{@pattern.inspect}, but should not have"
        end
      end

      class HaveExitedWith < Matcher  #:nodoc:
        def initialize(status)
          @status = status
        end

        def matches?(session)
          @session = session
          @status.to_i == session.exit_status
        end

        def failure_message_for_should
          "command should have exited with status #{@status}, but it exited with #{@session.exit_status}"
        end

        def failure_message_for_should_not
          "command should not have exited with status #{@status}"
        end
      end
    end
  end
end
