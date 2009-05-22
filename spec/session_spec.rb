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
        command = make_shell_command("touch #{output_name}")
        @session.run command
        @session.wait_until_done
        File.should exist?(output_name)
      end
    end

    it "should find the command in the PATH" do
      generate_file_name do |output_name|
        File.should_not exist?(output_name)  # sanity check
        clean_up output_name
        command = make_shell_command("touch #{output_name}")
        dirname, basename = File.split(command)

        @session.env['PATH'] = "#{dirname}:#{ENV['PATH']}"
        @session.run basename
        File.should exist?(output_name)
      end
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

  describe "#input" do
    it "should send the given string on standard input" do
      command = make_shell_command('cat <&0')
      @session.run command
      @session.input "hi"
      @session.wait_until_done
      @session.stdout.buffer.should == "hi"
    end
  end

  describe "#stdout" do
    it "should be nil before any commands are run" do
      @session.stdout.should be_nil
    end

    it "should return the standard output stream" do
      command = make_shell_command('echo out; echo err >&2')
      @session.run command
      @session.stdout.should be_a(CommandRat::Stream)
      @session.stdout.buffer == "out\n"
    end
  end

  describe "#stderr" do
    it "should be nil before any commands are run" do
      @session.stdout.should be_nil
    end

    it "should return the standard error stream" do
      command = make_shell_command('echo out; echo err >&2')
      @session.run command
      @session.stderr.should be_a(CommandRat::Stream)
      @session.stderr.buffer == "err\n"
    end
  end

  describe "Stream" do
    describe "#consume_to" do
      describe "when a string is given" do
        it "should return the string if found" do
          command = make_shell_command('echo hi')
          @session.run command
          @session.stdout.consume_to("hi").should == "hi"
        end

        it "should return nil if EOF is encountered" do
          command = make_shell_command('echo hi')
          @session.run command
          @session.stdout.consume_to("bye").should be_nil
        end

        it "consume up to the end of the given pattern" do
          command = make_shell_command('echo x; echo x')
          @session.run command
          @session.stdout.consume_to("x\n").should == "x\n"
          @session.stdout.consume_to("x\n").should == "x\n"
          @session.stdout.consume_to("x\n").should be_nil
        end

        it "should raise a Timeout if the timeout is exceeded" do
          command = make_shell_command('sleep 0.2; echo hi')

          # sanity check
          @session.run command
          @session.stdout.consume_to("hi").should == "hi"
          @session.wait_until_done

          @session.timeout = 0.1
          @session.run command
          lambda{@session.stdout.consume_to("hi")}.should raise_error(CommandRat::Timeout)
          @session.timeout = 0.2  # make sure we clean up properly
        end
      end

      describe "when a regexp is given" do
        it "should consume the output up to the end of the matched pattern" do
          command = make_shell_command('echo a.')
          @session.run command
          @session.stdout.consume_to(/./)[0].should == 'a'
          @session.stdout.consume_to(/./)[0].should == '.'
        end

        it "should return the match data" do
          command = make_shell_command('echo hi')
          @session.run command
          match = @session.stdout.consume_to(/hi/)
          match.should be_a(MatchData)
          match.to_a.should == ['hi']
        end

        it "should return nil if EOF is encountered" do
          command = make_shell_command('echo hi')
          @session.run command
          @session.stdout.consume_to(/bye/).should be_nil
        end

        it "should raise a Timeout if the timeout is exceeded" do
          command = make_shell_command('sleep 0.2; echo hi')

          # sanity check
          @session.run command
          @session.stdout.consume_to(/hi/)[0].should == "hi"
          @session.wait_until_done

          @session.timeout = 0.1
          @session.run command
          lambda{@session.stdout.consume_to(/hi/)}.should raise_error(CommandRat::Timeout)
          @session.timeout = 0.2  # make sure we clean up properly
        end
      end
    end

    describe "#next_line" do
      it "should return the next line of the output, without the line terminator" do
        command = make_shell_command('echo one; echo two')
        @session.run command
        @session.stdout.next_line.should == "one"
        @session.stdout.next_line.should == "two"
      end

      it "should recognize LF, CR, CRLF, and EOF as line terminators" do
        command = make_shell_command('cat <&0')
        @session.run command
        @session.input "one\ntwo\rthree\r\nfour"
        @session.close_input
        @session.stdout.next_line.should == 'one'
        @session.stdout.next_line.should == 'two'
        @session.stdout.next_line.should == 'three'
        @session.stdout.next_line.should == 'four'
      end

      it "should return nil if there are no more lines" do
        command = make_shell_command('')
        @session.run command
        @session.stdout.next_line.should be_nil
      end
    end

    describe "#eof?" do
      it "should return true if EOF has been encountered" do
        command = make_shell_command('')
        @session.run command
        @session.wait_until_done
        @session.stdout.eof?.should be_true
      end

      it "should return false if there is more buffered data" do
        command = make_shell_command('echo x')
        @session.run command
        @session.stdout.eof?.should be_false
      end

      it "should return true if the end of the buffer has been reached, and the EOF comes in soon" do
        command = make_shell_command('sleep 0.1')
        @session.run command
        @session.stdout.eof?.should be_true
      end

      it "should return true if the end of the buffer has been reached, and more data comes in later" do
        command = make_shell_command('sleep 0.1; echo x')
        @session.run command
        @session.stdout.eof?.should be_false
      end
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
      command = make_shell_command('sleep 0.1; exit 17')
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
      @session.stdout.buffer.should == "hi#$/"
    end
  end

  describe "#standard_output" do
    it "should return all data the command output on standard output" do
      command = make_shell_command('echo one; echo two; echo x >&2')
      @session.run command
      @session.stdout.consume_to(/n/)
      @session.standard_output.should == "one\ntwo\n"
    end
  end

  describe "#standard_error" do
    it "should return all data the command output on standard error" do
      command = make_shell_command('echo one >&2; echo two >&2; echo x')
      @session.run command
      @session.stdout.consume_to(/n/)
      @session.standard_error.should == "one\ntwo\n"
    end
  end

  describe "#receive_output?" do
    it "should return true if the given string follows on standard output" do
      command = make_shell_command('echo one; echo two; echo three; echo x >&2')
      @session.run command
      @session.receive_output?("one\n")
      @session.receive_output?("two\nthree\n")
    end
  end

  describe "#receive_error?" do
    it "should return true if the given string follows on standard error" do
      command = make_shell_command('echo one >&2; echo two >&2; echo three >&2; echo x')
      @session.run command
      @session.receive_error?("one\n")
      @session.receive_error?("two\nthree\n")
    end
  end

  describe "#no_more_output?" do
    it "should return true if there is no more data on standard output" do
      command = make_shell_command('')
      @session.run command
      @session.no_more_output?.should be_true
    end

    it "should return false if there is more data on standard output" do
      command = make_shell_command('echo x')
      @session.run command
      @session.no_more_output?.should be_false
    end
  end

  describe "#no_more_errors?" do
    it "should return true if there is no more data on standard error" do
      command = make_shell_command('')
      @session.run command
      @session.no_more_errors?.should be_true
    end

    it "should return false if there is more data on standard error" do
      command = make_shell_command('echo x >&2')
      @session.run command
      @session.no_more_errors?.should be_false
    end
  end
end
