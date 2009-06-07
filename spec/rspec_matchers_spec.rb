require 'spec_helper'
require 'command_rat/rspec/matchers'

describe "an RSpec context" do
  before do
    @context = Object.new
    @context.extend Spec::Matchers
    @session = CommandRat::Session.new
  end

  after do
    @session.wait_until_done
  end

  describe "#receive" do
    it "should match if the given string appears next on standard output" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
        |echo cc
      EOS
      @session.run command
      @context.receive("aa\nbb\n").matches?(@session).should be_true
    end

    it "should not match if the given string does not appear next on standard output" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo cc
      EOS
      @session.run command
      @context.receive("aa\nbb\n").matches?(@session).should be_false
    end

    it "should use standard error if the :on option is set to :standard_error" do
      command = make_shell_command(<<-EOS)
        |echo ax
        |echo aa >&2
      EOS
      @session.run command
      @context.receive("aa\n", :on => :standard_error).matches?(@session).should be_true
    end

    it "should use standard output if the :on option is set to :standard_output" do
      command = make_shell_command(<<-EOS)
        |echo ax >&2
        |echo aa
      EOS
      @session.run command
      @context.receive("aa\n", :on => :standard_output).matches?(@session).should be_true
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
      matcher = @context.receive("right\nright\nright\n")
      matcher.matches?(@session).should be_false
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

    it "should give a nice failure message for should when standard error is selected" do
      command = make_shell_command(<<-EOS)
        |echo right >&2
        |echo wrong >&2
        |echo right >&2
      EOS
      @session.run command
      matcher = @context.receive("right\nright\nright\n", :on => :standard_error)
      matcher.matches?(@session).should be_false
      matcher.failure_message_for_should.should == <<-EOS.gsub(/^ *\|/, '')
        |On standard error:
        |  Expected: | Actual:
        |  right     | right
        |  right     X wrong
        |  right     | right
      EOS
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command(<<-EOS)
        |echo one
        |echo two
        |echo three
      EOS
      @session.run command
      matcher = @context.receive("one\ntwo\nthree\n")
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard output:
        |  one
        |  two
        |  three
      EOS
    end

    it "should give a nice failure message for should not when standard error is selected" do
      command = make_shell_command(<<-EOS)
        |echo one >&2
        |echo two >&2
        |echo three >&2
      EOS
      @session.run command
      matcher = @context.receive("one\ntwo\nthree\n", :on => :standard_error)
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == <<-EOS.gsub(/^ *\|/, '')
        |Unexpected on standard error:
        |  one
        |  two
        |  three
      EOS
    end
  end

  describe "#receive_no_more_output" do
    it "should match if there is no more data on the standard output" do
      command = make_shell_command('sleep 0.2')
      @session.run command
      @context.receive_no_more_output.matches?(@session).should be_true
    end

    it "should not match if there is more data to come on standard output" do
      command = make_shell_command('sleep 0.2; echo')
      @session.run command
      @context.receive_no_more_output.matches?(@session).should be_false
    end

    it "should use standard error if the :on option is set to :standard_error" do
      command = make_shell_command('echo x; sleep 0.2')
      @session.run command
      @context.receive_no_more_output(:on => :standard_error).matches?(@session).should be_true
    end

    it "should use standard output if the :on option is set to :standard_output" do
      command = make_shell_command('echo x >&2; sleep 0.2')
      @session.run command
      @context.receive_no_more_output(:on => :standard_output).matches?(@session).should be_true
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('echo')
      @session.run command
      matcher = @context.receive_no_more_output
      matcher.matches?(@session).should be_false
      matcher.failure_message_for_should.should == "unexpected data on standard output"
    end

    it "should give a nice failure message for should when standard error is selected" do
      command = make_shell_command('echo >&2')
      @session.run command
      matcher = @context.receive_no_more_output(:on => :standard_error)
      matcher.matches?(@session).should be_false
      matcher.failure_message_for_should.should == "unexpected data on standard error"
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('')
      @session.run command
      matcher = @context.receive_no_more_output
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == "data expected on standard output"
    end

    it "should give a nice failure message for should not when standard error is selected" do
      command = make_shell_command('')
      @session.run command
      matcher = @context.receive_no_more_output(:on => :standard_error)
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == "data expected on standard error"
    end
  end

  describe "#have_exited_with" do
    it "should match if the command exited with the given exit status" do
      command = make_shell_command('exit 17')
      @session.run command
      @context.have_exited_with(17).matches?(@session).should be_true
    end

    it "should not match if the command exited with the given exit status" do
      command = make_shell_command('exit 23')
      @session.run command
      @context.have_exited_with(17).matches?(@session).should be_false
    end

    it "should implicity try to convert the given exit status to an integer" do
      command = make_shell_command('exit 17')
      @session.run command
      @context.have_exited_with('17').matches?(@session).should be_true
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('exit 18')
      @session.run command
      matcher = @context.have_exited_with(17)
      matcher.matches?(@session).should be_false  # sanity check
      matcher.failure_message_for_should.should == "command should have exited with status 17, but it exited with 18"
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('exit 17')
      @session.run command
      matcher = @context.have_exited_with(17)
      matcher.matches?(@session).should be_true  # sanity check
      matcher.failure_message_for_should_not.should == "command should not have exited with status 17"
    end
  end
end
