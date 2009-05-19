require 'spec_helper'
require 'command_rat/rspec/matchers'

describe "an RSpec context" do
  before do
    @context = Object.new
    @context.extend CommandRat::RSpec::Matchers
  end

  describe "#output" do
    it "should match if the pattern is found anywhere in the standard output" do
      command = make_shell_command(<<-EOS)
        |echo a b c
        |echo d x e
      EOS
      app = CommandRat::Session.run(command) do |app|
        @context.output(/x/).matches?(app).should be_true
      end
    end

    it "should not match if the pattern is not found anywhere in the standard output" do
      command = make_shell_command(<<-EOS)
        |echo a b c
        |echo d x e
      EOS
      app = CommandRat::Session.run(command) do |app|
        @context.output(/y/).matches?(app).should be_false
      end
    end

    it "should not match if the pattern only appears in the standard error" do
      command = make_shell_command(<<-EOS)
        |echo a b c >&2
        |echo d x e >&2
      EOS
      CommandRat::Session.run(command) do |app|
        @context.output(/x/).matches?(app).should be_false
      end
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('echo y')
      CommandRat::Session.run(command) do |app|
        matcher = @context.output('x')
        matcher.matches?(app).should be_false  # sanity check
        matcher.failure_message_for_should.should == "stdout did not contain \"x\""
      end
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('echo x')
      CommandRat::Session.run(command) do |app|
        matcher = @context.output('x')
        matcher.matches?(app).should be_true  # sanity check
        matcher.failure_message_for_should_not.should == "stdout contained \"x\", but should not have"
      end
    end
  end

  describe "#give_error" do
    it "should match if the pattern is found anywhere in the standard error" do
      command = make_shell_command(<<-EOS)
        |echo a b c >&2
        |echo d x e >&2
      EOS
      app = CommandRat::Session.run(command) do |app|
        @context.give_error(/x/).matches?(app).should be_true
      end
    end

    it "should not match if the pattern is not found anywhere in the standard error" do
      command = make_shell_command(<<-EOS)
        |echo a b c >&2
        |echo d x e >&2
      EOS
      app = CommandRat::Session.run(command) do |app|
        @context.give_error(/y/).matches?(app).should be_false
      end
    end

    it "should not match if the pattern only appears in the standard output" do
      command = make_shell_command(<<-EOS)
        |echo a b c
        |echo d x e
      EOS
      app = CommandRat::Session.run(command) do |app|
        @context.give_error(/x/).matches?(app).should be_false
      end
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('echo y')
      CommandRat::Session.run(command) do |app|
        matcher = @context.give_error('x')
        matcher.matches?(app).should be_false  # sanity check
        matcher.failure_message_for_should.should == "stderr did not contain \"x\""
      end
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('echo x >&2')
      CommandRat::Session.run(command) do |app|
        matcher = @context.give_error('x')
        matcher.matches?(app).should be_true  # sanity check
        matcher.failure_message_for_should_not.should == "stderr contained \"x\", but should not have"
      end
    end
  end

  describe "#have_exited_with" do
    it "should match if the command exited with the given exit status" do
      command = make_shell_command('exit 17')
      app = CommandRat::Session.run(command)
      @context.have_exited_with(17).matches?(app).should be_true
    end

    it "should not match if the command exited with the given exit status" do
      command = make_shell_command('exit 23')
      app = CommandRat::Session.run(command)
      @context.have_exited_with(17).matches?(app).should be_false
    end

    it "should implicity try to convert the given exit status to an integer" do
      command = make_shell_command('exit 17')
      app = CommandRat::Session.run(command)
      @context.have_exited_with('17').matches?(app).should be_true
    end

    it "should give a nice failure message for should" do
      command = make_shell_command('exit 18')
      app = CommandRat::Session.run(command)
      matcher = @context.have_exited_with(17)
      matcher.matches?(app).should be_false  # sanity check
      matcher.failure_message_for_should.should == "command should have exited with status 17, but it exited with 18"
    end

    it "should give a nice failure message for should not" do
      command = make_shell_command('exit 17')
      app = CommandRat::Session.run(command)
      matcher = @context.have_exited_with(17)
      matcher.matches?(app).should be_true  # sanity check
      matcher.failure_message_for_should_not.should == "command should not have exited with status 17"
    end
  end
end
