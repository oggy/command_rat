module CommandRat
  module RSpec
    module Matchers
      #
      # Matches if the given string appears next in standard output.
      #
      #     app = CommandRat::Session.run('echo hi')
      #     app.should output("hi\n")
      #
      def output(pattern)
        Output.new(pattern, :stderr)
      end

      #
      # Matches if the given string appears next in standard error.
      #
      #     app = CommandRat::Session.run('myprog')
      #     app.should error("Eek!\n")
      #
      def error(pattern)
        Error.new(pattern, :stderr)
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
        def initialize(string, stream)
          @string = string
        end

        def matches?(session)
          session.output?(@string)
        end

        def failure_message_for_should
          "incorrect string on standard output"
        end

        def failure_message_for_should_not
          "incorrect string on standard output"
        end
      end

      class Error < Matcher  #:nodoc:
        def initialize(string, stream)
          @string = string
        end

        def matches?(session)
          session.error?(@string)
        end

        def failure_message_for_should
          "incorrect string on standard error"
        end

        def failure_message_for_should_not
          "incorrect string on standard error"
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
