require 'spec/spec_helper'
require 'command_rat/rspec'

describe "an RSpec context" do
  before do
    @context = Object.new
    @context.extend Spec::Matchers
    @session = CommandRat::Session.new
  end

  after do
    @session.wait_until_done
  end

  describe "#include" do
    it "should match if the Stream#include? returns true for the given string" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
        |echo cc
      EOS
      @session.run command
      @session.standard_output.expects(:include?).with("aa\nbb\n").returns(true)
      @context.include("aa\nbb\n").matches?(@session.standard_output).should be_true
    end

    it "should not match if the Stream#include? returns false for the given string" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
        |echo cc
      EOS
      @session.run command
      @session.standard_output.expects(:include?).with("aa\nbb\n").returns(false)
      @context.include("aa\nbb\n").matches?(@session.standard_output).should be_false
    end

    it "should give a nice failure message for should when standard output is used" do
      command = make_shell_command(<<-EOS)
        |echo right
        |echo wrong
        |echo right
        |echo error line 1 >&2
        |echo error line 2 >&2
      EOS
      @session.run command
      @session.wait_until_done
      matcher = @context.include("right\nright\nright\n")
      matcher.matches?(@session.standard_output).should be_false
      matcher.failure_message_for_should.should == <<-EOS.gsub(/^ *\|/, '')
        |On standard output:
        |  Expected: | Actual:
        |  right     | right
        |  right     X wrong
        |  right     | right
        |Received on standard error:
        |  error line 1
        |  error line 2
        |(Received trailing newline, received EOF.)
      EOS
    end

    it "should give a nice failure message for should when standard error is used" do
      command = make_shell_command(<<-EOS)
        |echo right >&2
        |echo wrong >&2
        |echo right >&2
      EOS
      @session.run command
      matcher = @context.include("right\nright\nright\n")
      matcher.matches?(@session.standard_error).should be_false
      matcher.failure_message_for_should.should == <<-EOS.gsub(/^ *\|/, '')
        |On standard error:
        |  Expected: | Actual:
        |  right     | right
        |  right     X wrong
        |  right     | right
      EOS
    end

    it "should give a nice failure message for should not when standard output is used" do
      command = make_shell_command(<<-EOS)
        |echo one
        |echo two
        |echo three
      EOS
      @session.run command
      matcher = @context.include("one\ntwo\nthree\n")
      matcher.matches?(@session.standard_output).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard output:
        |  one
        |  two
        |  three
      EOS
    end

    it "should give a nice failure message for should not when standard error is used" do
      command = make_shell_command(<<-EOS)
        |echo one >&2
        |echo two >&2
        |echo three >&2
      EOS
      @session.run command
      matcher = @context.include("one\ntwo\nthree\n")
      matcher.matches?(@session.standard_error).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard error:
        |  one
        |  two
        |  three
      EOS
    end

    it "should not clobber the built-in RSpec #include" do
      @context.include(2, 3).matches?([1,2,3]).should be_true
    end
  end

  describe "#==" do
    it "should match if Stream#== returns true for the given string" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
      EOS
      @session.run command
      @session.standard_output.expects(:==).with("aa\nbb\n").returns(true)
      matcher = Spec::Matchers::OperatorMatcher.get(CommandRat::Stream, '==').new("aa\nbb\n")
      matcher.matches?(@session.standard_output).should be_true
    end

    it "should not match if Stream#== returns false for the given string" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
      EOS
      @session.run command
      @session.standard_output.expects(:==).with("aa\nbb\n").returns(false)
      matcher = Spec::Matchers::OperatorMatcher.get(CommandRat::Stream, '==').new("aa\nbb\n")
      matcher.matches?(@session.standard_output).should be_false
    end

    it "should give a nice failure message for should" do
      command = make_shell_command(<<-EOS)
        |echo right
        |echo wrong
        |echo right
        |echo error line 1 >&2
        |echo error line 2 >&2
      EOS
      @session.run command
      @session.wait_until_done
      matcher = Spec::Matchers::OperatorMatcher.get(CommandRat::Stream, '==').new("right\nright\nright\n")
      matcher.matches?(@session.standard_output).should be_false
      matcher.failure_message_for_should.should == <<-EOS.gsub(/^ *\|/, '')
        |On standard output:
        |  Expected: | Actual:
        |  right     | right
        |  right     X wrong
        |  right     | right
        |Received on standard error:
        |  error line 1
        |  error line 2
        |(Received trailing newline, received EOF.)
      EOS
    end

    it "should give a nice failure message for should when standard error is used" do
      command = make_shell_command(<<-EOS)
        |echo right >&2
        |echo wrong >&2
        |echo right >&2
      EOS
      @session.run command
      matcher = Spec::Matchers::OperatorMatcher.get(CommandRat::Stream, '==').new("right\nright\nright\n")
      matcher.matches?(@session.standard_error).should be_false
      matcher.failure_message_for_should.should == <<-EOS.gsub(/^ *\|/, '')
        |On standard error:
        |  Expected: | Actual:
        |  right     | right
        |  right     X wrong
        |  right     | right
      EOS
    end

    it "should give a nice failure message for should_not when standard output is used" do
      command = make_shell_command(<<-EOS)
        |echo one
        |echo two
        |echo three
      EOS
      @session.run command
      matcher = Spec::Matchers::OperatorMatcher.get(CommandRat::Stream, '==').new("one\ntwo\nthree\n")
      matcher.matches?(@session.standard_output).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard output:
        |  one
        |  two
        |  three
      EOS
    end

    it "should give a nice failure message for should_not when standard error is used" do
      command = make_shell_command(<<-EOS)
        |echo one >&2
        |echo two >&2
        |echo three >&2
      EOS
      @session.run command
      matcher = Spec::Matchers::OperatorMatcher.get(CommandRat::Stream, '==').new("one\ntwo\nthree\n")
      matcher.matches?(@session.standard_error).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard error:
        |  one
        |  two
        |  three
      EOS
    end
  end

  describe "next_contain" do
    it "should match if Stream#next? returns true for the given string" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
      EOS
      @session.run command
      @session.standard_output.expects(:next?).with("aa\nbb\n").returns(true)
      matcher = @context.next_contain("aa\nbb\n")
      matcher.matches?(@session.standard_output).should be_true
    end

    it "should not match if Stream#next? returns false for the given string" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
      EOS
      @session.run command
      @session.standard_output.expects(:next?).with("aa\nbb\n").returns(false)
      matcher = @context.next_contain("aa\nbb\n")
      matcher.matches?(@session.standard_output).should be_false
    end

    it "should give a nice failure message for should" do
      command = make_shell_command(<<-EOS)
        |echo right
        |echo wrong
        |echo right
        |echo error line 1 >&2
        |echo error line 2 >&2
      EOS
      @session.run command
      @session.wait_until_done
      matcher = @context.next_contain("right\nright\nright\n")
      matcher.matches?(@session.standard_output).should be_false
      matcher.failure_message_for_should.should == <<-EOS.gsub(/^ *\|/, '')
        |On standard output:
        |  Expected: | Actual:
        |  right     | right
        |  right     X wrong
        |  right     | right
        |Received on standard error:
        |  error line 1
        |  error line 2
        |(Received trailing newline, received EOF.)
      EOS
    end

    it "should give a nice failure message for should when standard error is used" do
      command = make_shell_command(<<-EOS)
        |echo right >&2
        |echo wrong >&2
        |echo right >&2
      EOS
      @session.run command
      matcher = @context.next_contain("right\nright\nright\n")
      matcher.matches?(@session.standard_error).should be_false
      matcher.failure_message_for_should.should == <<-EOS.gsub(/^ *\|/, '')
        |On standard error:
        |  Expected: | Actual:
        |  right     | right
        |  right     X wrong
        |  right     | right
      EOS
    end

    it "should give a nice failure message for should_not when standard output is used" do
      command = make_shell_command(<<-EOS)
        |echo one
        |echo two
        |echo three
      EOS
      @session.run command
      matcher = @context.next_contain("one\ntwo\nthree\n")
      matcher.matches?(@session.standard_output).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard output:
        |  one
        |  two
        |  three
      EOS
    end

    it "should give a nice failure message for should_not when standard error is used" do
      command = make_shell_command(<<-EOS)
        |echo one >&2
        |echo two >&2
        |echo three >&2
      EOS
      @session.run command
      matcher = @context.next_contain("one\ntwo\nthree\n")
      matcher.matches?(@session.standard_error).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard error:
        |  one
        |  two
        |  three
      EOS
    end
  end
end
