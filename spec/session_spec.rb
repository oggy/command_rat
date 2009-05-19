require 'spec_helper'
require 'fileutils'

describe "CommandRat::Session" do
  describe "#run" do
    it "should run the given command" do
      generate_file_name do |output_name|
        File.should_not exist?(output_name)  # sanity check
        clean_up output_name
        command = make_shell_command(<<-EOS)
          |touch #{output_name}
          |echo error >&2
        EOS
        rat = CommandRat::Session.run(command)
        File.should exist?(output_name)
      end
    end

    it "should find the command in the PATH" do
      command = make_shell_command('echo "found"')
      dirname, basename = File.split(command)
      rat = CommandRat::Session.new
      rat.stubs(:env).returns(ENV.to_hash.merge('PATH' => "/junk:#{dirname}:/more/junk"))
      rat.run(basename)
      rat.stdout.should == "found\n"
    end

    it "should raise CommandNotFound if the command is not in the PATH" do
      command = make_shell_command('echo "found"')
      dirname, basename = File.split(command)
      lambda{CommandRat::Session.run(basename)}.should raise_error(CommandRat::CommandNotFound)
    end

    it "should take a block which can simulate user sessions with #consume and #input" do
      command = make_shell_command(<<-EOS)
        |echo Enter something:
        |read response
        |echo $response!
      EOS
      block_run = false
      CommandRat::Session.run(command) do |rat|
        block_run = true
        rat.consume("Enter something:\n").should == "Enter something:\n"
        rat.input "hi\n"
        rat.consume("hi!\n").should == "hi!\n"
      end
      block_run.should be_true
    end
  end

  describe "#command" do
    it "should return the last command run" do
      command = make_shell_command(<<-EOS)
        |echo Enter something:
        |read response
        |echo $response!
      EOS
      rat = CommandRat::Session.run(command, 'a', 'b')
      rat.command.should == [command, 'a', 'b']
    end
  end

  describe "#consume" do
    it "should wait on the stream given by the :stream option" do
      command = make_shell_command(<<-EOS)
        |echo hi >&2
      EOS

      CommandRat::Session.run(command) do |rat|
        rat.consume("hi\n", :on => :stderr).should == "hi\n"
      end
    end

    it "should raise an ArgumentError if an invalid stream option is given" do
      command = make_shell_command(<<-EOS)
        |echo hi
      EOS
      rat = CommandRat::Session.run(command) do |rat|
        lambda{rat.consume("hi\n", :on => :blarg)}.should raise_error(ArgumentError)
      end
    end

    describe "when a string is given" do
      it "should consume the output up to the end of the string" do
        command = make_shell_command(<<-EOS)
          |echo one
          |echo two
        EOS
        rat = CommandRat::Session.run(command) do |rat|
          rat.consume("one\n").should == "one\n"
        end
        rat.stdout.should == "two\n"
      end

      it "should return the string if found" do
        command = make_shell_command(<<-EOS)
          |echo hi
        EOS

        CommandRat::Session.run(command) do |rat|
          rat.consume("hi").should == "hi"
        end
      end

      it "should return nil if EOF is encountered" do
        command = make_shell_command(<<-EOS)
          |echo hi
        EOS

        CommandRat::Session.run(command) do |rat|
          rat.consume("bye").should be_nil
        end
      end

      it "should raise a Timeout if the timeout is exceeded" do
        command = make_shell_command(<<-EOS)
          |sleep 0.2
          |echo hi
        EOS

        rat = CommandRat::Session.new

        # sanity check
        rat.run(command) do
          rat.consume("hi").should == "hi"
        end

        rat.timeout = 0.1
        rat.run(command) do
          lambda{rat.consume("hi")}.should raise_error(CommandRat::Timeout)
        end
      end
    end

    describe "when a regexp is given" do
      it "should consume the output up to the end of the matched pattern" do
        command = make_shell_command(<<-EOS)
          |echo a.
        EOS
        rat = CommandRat::Session.run(command) do |rat|
          rat.consume(/./)[0].should == 'a'
        end
        rat.stdout.should == ".\n"
      end

      it "should return the match data" do
        command = make_shell_command(<<-EOS)
          |echo hi
        EOS

        CommandRat::Session.run(command) do |rat|
          match = rat.consume(/hi/)
          match.should be_a(MatchData)
          match.to_a.should == ['hi']
        end
      end

      it "should return nil if EOF is encountered" do
        command = make_shell_command(<<-EOS)
          |echo hi
        EOS

        CommandRat::Session.run(command) do |rat|
          rat.consume(/bye/).should be_nil
        end
      end

      it "should raise a Timeout if the timeout is exceeded" do
        command = make_shell_command(<<-EOS)
          |sleep 0.2
          |echo hi
        EOS

        rat = CommandRat::Session.new

        # sanity check
        rat.run(command) do
          rat.consume(/hi/)[0].should == "hi"
        end

        rat.timeout = 0.1
        rat.run(command) do
          lambda{rat.consume(/hi/)}.should raise_error(CommandRat::Timeout)
        end
      end
    end
  end

  describe "#stdout" do
    it "raises a RunError if inside a #run block" do
      command = make_shell_command(<<-EOS)
        |read string
        |echo $string!
      EOS
      rat = CommandRat::Session.run(command) do |rat|
        lambda{rat.stdout}.should raise_error(CommandRat::RunError)
      end
    end

    it "should return any unconsumed data on standard output after a #run block" do
      command = make_shell_command(<<-EOS)
        |echo out1
        |echo out2
        |echo err >&2
      EOS
      rat = CommandRat::Session.run(command) do |rat|
        rat.consume("out1\n")
      end
      rat.stdout.should == "out2\n"
    end

    it "should return the standard output after #run is called without a block" do
      command = make_shell_command(<<-EOS)
        |echo out
        |echo err >&2
      EOS
      rat = CommandRat::Session.run(command)
      rat.stdout.should == "out\n"
    end
  end

  describe "#stderr" do
    it "raises a RunError if inside a #run block" do
      command = make_shell_command(<<-EOS)
        |read string
        |echo $string!
      EOS
      rat = CommandRat::Session.run(command) do |rat|
        lambda{rat.stdout}.should raise_error(CommandRat::RunError)
      end
    end

    it "should return any unconsumed data on standard error after a #run block" do
      command = make_shell_command(<<-EOS)
        |echo out
        |echo err1 >&2
        |echo err2 >&2
      EOS
      rat = CommandRat::Session.run(command) do |rat|
        rat.consume("err1\n", :on => :stderr)
      end
      rat.stderr.should == "err2\n"
    end

    it "should return the standard error after #run is called without a block" do
      command = make_shell_command(<<-EOS)
        |echo out
        |echo err >&2
      EOS
      rat = CommandRat::Session.run(command)
      rat.stderr.should == "err\n"
    end
  end

  describe "#exit_status" do
    it "raises a RunError if inside a #run block" do
      command = make_shell_command(<<-EOS)
        |read string
        |echo $string!
      EOS
      rat = CommandRat::Session.run(command) do |rat|
        lambda{rat.exit_status}.should raise_error(CommandRat::RunError)
      end
    end

    it "should return the exit status after #run is called without a block" do
      command = make_shell_command(<<-EOS)
        |exit 17
      EOS
      rat = CommandRat::Session.run(command)
      rat.exit_status.should == 17
    end

    it "should return the exit status after a #run block" do
      command = make_shell_command(<<-EOS)
        |exit 17
      EOS
      rat = CommandRat::Session.run(command) do
      end
      rat.exit_status.should == 17
    end
  end

  describe "#enter" do
    it "should append a record separator if necessary" do
      command = make_shell_command(<<-EOS)
        |cat <&0
      EOS
      rat = CommandRat::Session.run(command) do |rat|
        rat.enter "hi"
      end
      rat.stdout.should == "hi#$/"
    end
  end

  describe "#expect" do
    it "should return the matched string if the next line contains the given string" do
      command = make_shell_command(<<-EOS)
          |echo 'x yes x'
        EOS
      CommandRat::Session.run(command) do |rat|
        rat.expect('yes').should == 'yes'
      end
    end

    it "should return the match if the next line contains the given regexp" do
      command = make_shell_command(<<-EOS)
          |echo 'x.x'
        EOS
      CommandRat::Session.run(command) do |rat|
        match = rat.expect(/./)
        match.should be_a(MatchData)
        match[0].should == 'x'
      end
    end

    it "should return nil if the next line does not contain the given string" do
      command = make_shell_command(<<-EOS)
          |echo 'x yes x'
        EOS
      CommandRat::Session.run(command) do |rat|
        rat.expect('no').should be_nil
      end
    end

    it "should consume the line" do
      command = make_shell_command(<<-EOS)
          |echo x one x
          |echo x two x
        EOS
      rat = CommandRat::Session.run(command) do |rat|
        rat.expect('one').should == 'one'
      end
      rat.stdout.should == "x two x\n"
    end
  end
end
