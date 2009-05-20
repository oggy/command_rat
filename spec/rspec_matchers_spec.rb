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
    it "should match if the next line of standard output contains the given pattern" do
      command = make_shell_command(<<-EOS)
        |echo ax
        |echo ay
      EOS
      @session.run command
      @context.output(/x/).matches?(@session).should be_true
      @context.output(/y/).matches?(@session).should be_true
    end

    it "should not match if the next line of standard output does not contain the given pattern" do
      command = make_shell_command('echo a')
      @session.run command
      @context.output(/x/).matches?(@session).should be_false
    end

    it "should not match if the pattern only appears in the standard error" do
      command = make_shell_command(<<-EOS)
        |echo a
        |echo x >&2
      EOS
      @session.run command
      @context.output(/x/).matches?(@session).should be_false
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('echo y')
      @session.run command
      matcher = @context.output('x')
      matcher.matches?(@session).should be_false
      matcher.failure_message_for_should.should == "next line of stdout did not contain \"x\""
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('echo x')
      @session.run command
      matcher = @context.output('x')
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == "next line of stdout contained \"x\", but should not have"
    end
  end

  describe "#give_error" do
    it "should match if the next line of standard error contains the given pattern" do
      command = make_shell_command(<<-EOS)
        |echo ax >&2
        |echo ay >&2
      EOS
      @session.run command
      @context.give_error(/x/).matches?(@session).should be_true
      @context.give_error(/y/).matches?(@session).should be_true
    end

    it "should not match if the next line of standard error does not contain the given pattern" do
      command = make_shell_command('echo a >&2')
      @session.run command
      @context.give_error(/x/).matches?(@session).should be_false
    end

    it "should not match if the pattern only appears in the standard output" do
      command = make_shell_command(<<-EOS)
        |echo a >&2
        |echo x
      EOS
      @session.run command
      @context.give_error(/x/).matches?(@session).should be_false
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('echo y >&2')
      @session.run command
      matcher = @context.give_error('x')
      matcher.matches?(@session).should be_false
      matcher.failure_message_for_should.should == "next line of stderr did not contain \"x\""
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('echo x >&2')
      @session.run command
      matcher = @context.give_error('x')
      matcher.matches?(@session).should be_true
      matcher.failure_message_for_should_not.should == "next line of stderr contained \"x\", but should not have"
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
