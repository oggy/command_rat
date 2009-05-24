module CommandRat
  module RSpec
    module Matchers
      #
      # Matches if the given string appears next in standard output.
      #
      # An :on option may be set to :stdout or :stderr to specify the
      # stream.  Default is :stdout.
      #
      #     app = CommandRat::Session.run('echo hi')
      #     app.should receive("hi\n")
      #
      #     app = CommandRat::Session.run('echo hi >&2')
      #     app.should receive("hi\n", :on => :stderr)
      #
      def receive(pattern, options={})
        Receive.new(pattern, options)
      end

      #
      # Matches if there is no more output on standard output.
      #
      # An :on option may be set to :stdout or :stderr to specify the
      # stream.  Default is :stdout.
      #
      #     app = CommandRat::Session.run('myprog')
      #     app.should receive_no_more_output
      #
      #     app = CommandRat::Session.run('myprog')
      #     app.should receive_no_more_output(:on => :stderr)
      #
      def receive_no_more_output(options={})
        ReceiveNoMore.new(options)
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

        def stream(options)
          options[:on] == :stderr ? 'standard error' : 'standard output'
        end
      end

      class Receive < Matcher
        def initialize(string, options={})
          @string = string
          @options = options
        end

        def matches?(session)
          @session = session
          session.receive?(@string, @options)
        end

        def failure_message_for_should
          diff = Diff.new(:left_heading => 'Expected:',
                          :right_heading => 'Actual:',
                          :left => @string,
                          :right => @session.peek(@string.length, @options))
          "On #{stream(@options)}:\n#{diff.to_s.gsub(/^/, '  ')}"
        end

        def failure_message_for_should_not
          "Unexpected on #{stream(@options)}:\n#{@string.gsub(/^/, '  ')}"
        end
      end

      class ReceiveNoMore < Matcher
        def initialize(options)
          @options = options
        end

        def matches?(session)
          session.no_more_output?(@options)
        end

        def failure_message_for_should
          "unexpected data on #{stream(@options)}"
        end

        def failure_message_for_should_not
          "data expected on #{stream(@options)}"
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
