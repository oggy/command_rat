require 'spec_helper'
require 'command_rat/rspec/matchers'

describe "an RSpec context" do
  before do
    @context = Object.new
    @context.extend CommandRat::RSpec::Matchers
    @session = CommandRat::Session.new
  end

  after do
    @session.wait_until_done
  end

  describe "#output" do
    it "should match if the given string appears next on standard output" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo bb
        |echo cc
      EOS
      @session.run command
      @context.output("aa\nbb\n").matches?(@session).should be_true
    end

    it "should not match if the given string does not appear next on standard output" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo cc
      EOS
      @session.run command
      @context.output("aa\nbb\n").matches?(@session).should be_false
    end

    it "should not match if the given string appears on standard error, but not standard output" do
      command = make_shell_command(<<-EOS)
        |echo ax
        |echo aa >&2
      EOS
      @session.run command
      @context.output("aa\n").matches?(@session).should be_false
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('echo y')
      @session.run command
      matcher = @context.output('x')
      matcher.matches?(@session).should be_false
      matcher.failure_message_for_should.should == "incorrect string on standard output"
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('echo x')
      @session.run command
      matcher = @context.output('x')
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == "incorrect string on standard output"
    end
  end

  describe "#error" do
    it "should match if the given string appears next on standard error" do
      command = make_shell_command(<<-EOS)
        |echo aa >&2
        |echo bb >&2
        |echo cc >&2
      EOS
      @session.run command
      @context.error("aa\nbb\n").matches?(@session).should be_true
    end

    it "should not match if the given string does not appear next on standard error" do
      command = make_shell_command(<<-EOS)
        |echo aa
        |echo cc
      EOS
      @session.run command
      @context.error("aa\nbb\n").matches?(@session).should be_false
    end

    it "should not match if the given string appears on standard output, but not standard error" do
      command = make_shell_command(<<-EOS)
        |echo ax >&2
        |echo aa
      EOS
      @session.run command
      @context.error("aa\n").matches?(@session).should be_false
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('echo y >&2')
      @session.run command
      matcher = @context.error('x')
      matcher.matches?(@session).should be_false
      matcher.failure_message_for_should.should == "incorrect string on standard error"
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('echo x >&2')
      @session.run command
      matcher = @context.error('x')
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == "incorrect string on standard error"
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
