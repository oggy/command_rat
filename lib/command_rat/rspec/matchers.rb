module CommandRat
  module RSpec
    module Matchers
      def self.included(mod)
        mod.send(:alias_method, :include_without_command_rat, :include)
        mod.send(:alias_method, :include, :include_with_command_rat)
      end

      #
      # Matches if the stream contains the given string.
      #
      def include_with_command_rat(string, *args)
        matcher = Include.new(string)
        supermatcher = include_without_command_rat(string, *args)
        Delegator.new(CommandRat::Stream, matcher, supermatcher)
      end

      #
      # Matches if the stream contains the given string next, and
      # advances the stream's cursor.
      #
      # This lets you check the full output of the command one piece
      # at a time.
      #
      #     session.standard_output.should next_contain("Creating new database.\n")
      #     session.standard_output.should next_contain("Password: ")
      #
      def next_contain(string)
        NextContain.new(string)
      end

      #
      # Matches if the command exited with the given status.
      #
      #     app = CommandRat::Session.run('echo')
      #     app.should exit_with(0)
      #
      def exit_with(status)
        ExitWith.new(status)
      end

      # Abstract Matcher.
      class Matcher  #:nodoc:
        protected  # -------------------------------------------------

        def stream(options)
          options[:on] == :standard_error ? 'standard error' : 'standard output'
        end
      end

      class Include < Matcher
        def initialize(string)
          @string = string
        end

        def matches?(stream)
          @stream = stream
          stream.include?(@string)
        end

        def failure_message_for_should
          diff = Diff.new(:left_heading => 'Expected:',
                          :right_heading => 'Actual:',
                          :left_body => @string,
                          :right_body => @stream.response)
          message = "On #{@stream.name}:\n#{diff.to_s.gsub(/^/, '  ')}"
          # If we didn't print out standard_error above, print it
          # here, since it may contain useful error messages.
          unless @stream.name == 'standard error'
            message << @stream.session.standard_error.inspect
          end
          message
        end

        def failure_message_for_should_not
          "Unexpected on #{@stream.name}:\n#{@string.gsub(/^/, '  ')}"
        end
      end

      class NextContain < Matcher
        def initialize(string)
          @string = string
        end

        def matches?(stream)
          @stream = stream
          stream.next?(@string)
        end

        def failure_message_for_should
          diff = Diff.new(:left_heading => 'Expected:',
                          :right_heading => 'Actual:',
                          :left_body => @string,
                          :right_body => @stream.response)
          message = "On #{@stream.name}:\n#{diff.to_s.gsub(/^/, '  ')}"
          # If we didn't print out standard_error above, print it
          # here, since it may contain useful error messages.
          unless @stream.name == 'standard error'
            message << @stream.session.standard_error.inspect
          end
          message
        end

        def failure_message_for_should_not
          "Unexpected on #{@stream.name}:\n#{@string.gsub(/^/, '  ')}"
        end
      end

      class ExitWith < Matcher  #:nodoc:
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

      class StreamEqual
        def initialize(string)
          @string = string
        end

        def matches?(stream)
          @stream = stream
          @stream == @string
        end

        def failure_message_for_should
          diff = Diff.new(:left_heading => 'Expected:',
                          :right_heading => 'Actual:',
                          :left_body => @string,
                          :right_body => @stream.response)
          message = "On #{@stream.name}:\n#{diff.to_s.gsub(/^/, '  ')}"
          # If we didn't print out standard_error above, print it
          # here, since it may contain useful error messages.
          unless @stream.name == 'standard error'
            message << @stream.session.standard_error.inspect
          end
          message
        end

        def failure_message_for_should_not
          "Unexpected on #{@stream.name}:\n#{@string.gsub(/^/, '  ')}"
        end
      end

      #
      # :call-seq:
      #   session.standard_output.should == "Hi.\n"
      #
      # Passes if the session's standard output since the last user
      # action contains the given string.
      #
      Spec::Matchers::OperatorMatcher.register(CommandRat::Stream, '==', StreamEqual)

      #
      # Decorates a matcher so that it can delegate to a built-in
      # RSpec matcher if the test subject isn't of the expected class.
      #
      class Delegator
        def initialize(klass, matcher, supermatcher)
          @klass = klass
          @matcher = matcher
          @supermatcher = supermatcher
          @subject = nil
        end

        def matches?(subject)
          @subject = subject
          select_matcher.matches?(subject)
        end

        def failure_message_for_should
          select_matcher.failure_message_for_should
        end

        def failure_message_for_should_not
          select_matcher.failure_message_for_should_not
        end

        private  # ---------------------------------------------------

        def select_matcher
          @subject.is_a?(@klass) ? @matcher : @supermatcher
        end
      end
    end
  end
end

Spec::Matchers.send :include, CommandRat::RSpec::Matchers
