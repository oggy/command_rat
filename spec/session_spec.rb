require 'spec_helper'
require 'fileutils'

describe "CommandRat::Session" do
  before do
    @session = CommandRat::Session.new
  end

  after do
    @session.wait_until_done
  end

  describe "#run" do
    it "should run the given command" do
      generate_file_name do |output_name|
        File.should_not exist?(output_name)  # sanity check
        clean_up output_name
        command = make_shell_command(<<-EOS)
          |touch #{output_name}
          |echo error >&2
        EOS
        @session.run command
        @session.wait_until_done
        File.should exist?(output_name)
      end
    end

    it "should find the command in the PATH" do
      command = make_shell_command('echo "found"')
      dirname, basename = File.split(command)

      @session.env['PATH'] = "#{dirname}:#{ENV['PATH']}"
      @session.run basename
      @session.stdout.should == "found\n"
    end
  end

  describe "#running?" do
    it "should return true while and only while the process is running" do
      command = make_shell_command('sleep 0.2')
      @session.running?.should be_false

      @session.run command
      @session.running?.should be_true

      @session.wait_until_done
      @session.running?.should be_false
    end
  end

  describe "#env" do
    it "should be used to set the environment for commands" do
      command = make_shell_command('echo $X:$Y:$Z')
      ENV['Z'] = 'zz'
      @session.run command
      @session.env = {'X' => 'xx', 'Y' => 'yy'}
      @session.wait_until_done
      @session.stdout == "xx:yy:"
      ENV['Z'] = nil
    end
  end

  describe "#command" do
    it "should return the last command run" do
      command = make_shell_command(<<-EOS)
        |echo Enter something:
        |read response
        |echo $response!
      EOS
      @session.run command, 'a', 'b'
      @session.command.should == [command, 'a', 'b']
    end
  end

  describe "#consume_to" do
    it "should wait on the stream given by the :stream option" do
      command = make_shell_command('echo hi >&2')
      @session.run command
      @session.consume_to("hi\n", :on => :stderr).should == "hi\n"
    end

    it "should raise an ArgumentError if an invalid stream option is given" do
      command = make_shell_command('echo hi')
      @session.run command
      lambda{@session.consume_to("hi\n", :on => :blarg)}.should raise_error(ArgumentError)
    end

    describe "when a string is given" do
      it "should consume the output up to the end of the string" do
        command = make_shell_command(<<-EOS)
          |echo x
          |echo x
        EOS
        @session.run command
        @session.consume_to("x\n").should == "x\n"
        @session.consume_to("x\n").should == "x\n"
        @session.consume_to("x\n").should be_nil
      end

      it "should return the string if found" do
        command = make_shell_command('echo hi')
        @session.run command
        @session.consume_to("hi").should == "hi"
      end

      it "should return nil if EOF is encountered" do
        command = make_shell_command('echo hi')
        @session.run command
        @session.consume_to("bye").should be_nil
      end

      it "should raise a Timeout if the timeout is exceeded" do
        command = make_shell_command(<<-EOS)
          |sleep 0.2
          |echo hi
        EOS

        # sanity check
        @session.run command
        @session.consume_to("hi").should == "hi"
        @session.wait_until_done

        @session.timeout = 0.1
        @session.run command
        lambda{@session.consume_to("hi")}.should raise_error(CommandRat::Timeout)
      end
    end

    describe "when a regexp is given" do
      it "should consume the output up to the end of the matched pattern" do
        command = make_shell_command('echo a.')
        @session.run command
        @session.consume_to(/./)[0].should == 'a'
        @session.consume_to(/./)[0].should == '.'
      end

      it "should return the match data" do
        command = make_shell_command('echo hi')
        @session.run command
        match = @session.consume_to(/hi/)
        match.should be_a(MatchData)
        match.to_a.should == ['hi']
      end

      it "should return nil if EOF is encountered" do
        command = make_shell_command('echo hi')
        @session.run command
        @session.consume_to(/bye/).should be_nil
      end

      it "should raise a Timeout if the timeout is exceeded" do
        command = make_shell_command(<<-EOS)
          |sleep 0.2
          |echo hi
        EOS

        # sanity check
        @session.run command
        @session.consume_to(/hi/)[0].should == "hi"
        @session.wait_until_done

        @session.timeout = 0.1
        @session.run command
        lambda{@session.consume_to(/hi/)}.should raise_error(CommandRat::Timeout)
      end
    end
  end

  describe "#input" do
    it "should send the given string on standard input" do
      command = make_shell_command('cat <&0')
      @session.run command
      @session.input "hi"
      @session.wait_until_done
      @session.stdout.should == "hi"
    end
  end

  describe "#stdout" do
    it "should be nil before any commands are run" do
      @session.stdout.should be_nil
    end

    it "should be '' immediately after the command is run" do
      command = make_shell_command('')
      @session.run command
      @session.stdout.should == ''
    end

    it "should return everything the current command has output to standard output" do
      command = make_shell_command('echo a; echo b')
      @session.run command
      @session.consume_to(/\n/)
      @session.consume_to(/\n/)
      @session.stdout.should == "a\nb\n"
    end
  end

  describe "#stderr" do
    it "should be nil before any commands are run" do
      @session.stderr.should be_nil
    end

    it "should be '' immediately after the command is run" do
      command = make_shell_command('')
      @session.run command
      @session.stderr.should == ''
    end

    it "should return everything the current command has output to standard error" do
      command = make_shell_command('echo a >&2; echo b >&2')
      @session.run command
      @session.consume_to(/\n/, :on => :stderr)
      @session.consume_to(/\n/, :on => :stderr)
      @session.stderr.should == "a\nb\n"
    end
  end

  describe "#exit_status" do
    it "should be nil before any commands are run" do
      @session.exit_status.should be_nil
    end

    it "should be nil after the command is run, but before it has exited" do
      command = make_shell_command('')
      @session.stderr.should be_nil
    end

    it "should wait until the command is done, and return the exit status" do
      command = make_shell_command(<<-EOS)
        |sleep 0.1
        |exit 17
      EOS
      @session.run command
      @session.exit_status.should == 17
    end
  end

  describe "#enter" do
    it "should append a record separator if necessary" do
      command = make_shell_command('cat <&0')
      @session.run command
      @session.enter "hi"
      @session.wait_until_done
      @session.stdout.should == "hi#$/"
    end
  end

  describe "#output?" do
    it "should return true if the next line contains the given string" do
      command = make_shell_command('echo x yes x')
      @session.run command
      @session.output?('yes').should be_true
    end

    it "should return true if the next line contains the given regexp" do
      command = make_shell_command('echo a')
      @session.run command
      @session.output?(/./).should be_true
    end

    it "should return false if the next line does not contain the given string" do
      command = make_shell_command('echo x yes x')
      @session.run command
      @session.output?('no').should be_false
    end

    it "should return false if the next line does not contain the given regexp" do
      command = make_shell_command('echo a')
      @session.run command
      @session.output?(/b/).should be_false
    end

    it "should consume the next line" do
      command = make_shell_command(<<-EOS)
        |echo a
        |echo b
        |echo a
      EOS
      @session.run command
      @session.output?(/a/).should be_true
      @session.output?(/a/).should be_false
      @session.output?(/a/).should be_true
    end

    it "should use standard error if :on => :stderr is given" do
      command = make_shell_command('echo x yes x >&2')
      @session.run command
      @session.output?('yes', :on => :stderr).should be_true
    end
  end
end
