module CommandRat
  module RSpec
    module Matchers
      #
      # Matches if the given string appears next in standard output.
      #
      #     app = CommandRat::Session.run('echo hi')
      #     app.should receive_output("hi\n")
      #
      def receive_output(pattern)
        ReceiveOutput.new(pattern, :output)
      end

      #
      # Matches if the given string appears next in standard error.
      #
      #     app = CommandRat::Session.run('myprog')
      #     app.should receive_error("Eek!\n")
      #
      def receive_error(pattern)
        ReceiveOutput.new(pattern, :error)
      end

      #
      # Matches if there is no more output on standard output.
      #
      #     app = CommandRat::Session.run('myprog')
      #     app.should receive_no_more_output
      #
      def receive_no_more_output
        ReceiveNoMoreOutput.new(:output)
      end

      #
      # Matches if there is no more output on standard output.
      #
      #     app = CommandRat::Session.run('myprog')
      #     app.should receive_no_more_errors
      #
      def receive_no_more_errors
        ReceiveNoMoreOutput.new(:error)
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

      class ReceiveOutput < Matcher
        def initialize(string, stream)
          @string = string
          @stream = stream
        end

        def matches?(session)
          @session = session
          session.send("receive_#{@stream}?", @string)
        end

        def failure_message_for_should
          diff = Diff.new(:left_heading => 'Expected:',
                          :right_heading => 'Actual:',
                          :left => @string,
                          :right => @session.send("peek_at_#{@stream}", (@string.length)))
          "On standard #{@stream}:\n#{diff.to_s.gsub(/^/, '  ')}"
        end

        def failure_message_for_should_not
          "Unexpected on standard #{@stream}:\n#{@string.gsub(/^/, '  ')}"
        end
      end

      class ReceiveNoMoreOutput < Matcher
        def initialize(stream)
          @stream = stream
        end

        def matches?(session)
          if @stream == :error
            method = :no_more_errors?
          else
            method = :no_more_output?
          end
          session.send(method)
        end

        def failure_message_for_should
          "unexpected data on standard #{@stream}"
        end

        def failure_message_for_should_not
          "data expected on standard #{@stream}"
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

Spec::Matchers.send :include, CommandRat::RSpec::Matchers
