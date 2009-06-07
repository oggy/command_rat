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
      output_name = generate_file
      command = make_shell_command("touch #{output_name}")

      FileUtils.rm_f output_name
      @session.run command
      @session.wait_until_done
      File.exist?(output_name).should be_true
    end

    it "should find the command in the PATH" do
      output_name = generate_file
      command = make_shell_command("touch #{output_name}")
      dirname, basename = File.split(command)

      FileUtils.rm_f output_name
      @session.env['PATH'] = "#{dirname}:#{ENV['PATH']}"
      @session.run basename
      @session.wait_until_done
      File.exist?(output_name).should be_true
    end

    it "should parse the given command like a shell" do
      output_name = generate_file
      command = make_shell_command(<<-EOS)
        |echo $1 >> #{output_name}
        |echo $2 >> #{output_name}
        |echo $3 >> #{output_name}
      EOS

      @session.run "#{command} one 'two three' four\\ five"
      @session.wait_until_done
      File.read(output_name).should == "one\ntwo three\nfour five\n"
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
      @session.run "#{command} a b"
      @session.command.should == "#{command} a b"
    end
  end

  describe "#send_input" do
    it "should send the given string on standard input" do
      command = make_shell_command('cat <&0')
      @session.run command
      @session.send_input "hi"
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
        @session.send_input "one\ntwo\rthree\r\nfour"
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

    describe "#peek" do
      it "should return everything available on the stream" do
        command = make_shell_command('echo 1234; sleep 0.4; echo 5678')
        @session.run command
        sleep 0.2
        @session.stdout.peek.should == "1234\n"
      end

      it "should not consume anything" do
        command = make_shell_command('echo 1234')
        @session.run command
        @session.wait_until_done
        @session.peek
        @session.stdout.peek.should == "1234\n"
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

  describe "#receive?" do
    it "should return true if the given string follows on standard output" do
      command = make_shell_command('echo x >&2; echo one; echo two; echo three')
      @session.run command
      @session.receive?("one\n").should be_true
      @session.receive?("two\nthree\n").should be_true
    end

    it "should return false if the given string does not follow on standard output" do
      command = make_shell_command('echo one; echo x >&2')
      @session.run command
      @session.receive?("one\ntwo/").should be_false
    end

    it "should not consume anything if it returns false" do
      command = make_shell_command('echo one; echo x')
      @session.run command
      @session.receive?("one\ntwo\n").should be_false  # sanity check
      @session.receive?("one\n").should be_true
    end

    it "should use standard error if the :on option is set to :stderr" do
      command = make_shell_command('echo x; echo one >&2; echo two >&2; echo three >&2')
      @session.run command
      @session.receive?("one\n", :on => :stderr).should be_true
      @session.receive?("two\nthree\n", :on => :stderr).should be_true
    end

    it "should use standard output if the :on option is set to :stdout" do
      command = make_shell_command('echo x >&2; echo one; echo two; echo three')
      @session.run command
      @session.receive?("one\n", :on => :stdout).should be_true
      @session.receive?("two\nthree\n", :on => :stdout).should be_true
    end

    it "should raise an ArgumentError if the :on option is set to something else" do
      command = make_shell_command('')
      @session.run command
      lambda{@session.receive?('', :on => :bad_stream)}.should raise_error(ArgumentError)
    end
  end

  describe "#no_more_output?" do
    it "should return true if there is no more data on standard output" do
      command = make_shell_command('echo x >&2')
      @session.run command
      @session.no_more_output?.should be_true
    end

    it "should return false if there is more data on standard output" do
      command = make_shell_command('echo x')
      @session.run command
      @session.no_more_output?.should be_false
    end

    it "should use standard error if the :on option is set to :stderr" do
      command = make_shell_command('echo x')
      @session.run command
      @session.no_more_output?(:on => :stderr).should be_true
    end

    it "should use standard output if the :on option is set to :stdout" do
      command = make_shell_command('echo x >&2')
      @session.run command
      @session.no_more_output?(:on => :stdout).should be_true
    end

    it "should raise an ArgumentError if the :on option is set to something else" do
      command = make_shell_command('echo x >&2')
      @session.run command
      lambda{@session.no_more_output?(:on => :bad_stream)}.should raise_error(ArgumentError)
    end
  end

  describe "#peek" do
    it "should return the available data on standard output" do
      command = make_shell_command('echo out; echo err >&2')
      @session.run command
      @session.wait_until_done
      @session.peek.should == "out\n"
    end

    it "should use standard error if the :on option is set to :stderr" do
      command = make_shell_command('echo out; echo err >&2')
      @session.run command
      @session.wait_until_done
      @session.peek(:on => :stderr).should == "err\n"
    end
  end

  describe "#inspect" do
    it "should show everything received on standard output and standard error" do
      command = make_shell_command(<<-EOS)
        |echo one
        |echo two
        |echo one! >&2
        |echo two! >&2
      EOS
      @session.run command
      @session.wait_until_done
      @session.inspect.should == <<-EOS.gsub(/^ *\|/, '')
        |CommandRat::Session running: #{command}
        |  Received on standard output:
        |    one
        |    two
        |  (Received trailing newline, received EOF.)
        |  Received on standard error:
        |    one!
        |    two!
        |  (Received trailing newline, received EOF.)
      EOS
    end

    it "should indicate trailing newlines and EOFs" do
      command = make_ruby_command(<<-EOS)
        |STDOUT.print "one"; STDOUT.close
        |STDERR.print "two\n"; STDERR.flush
        |sleep 0.8
      EOS

      @session.run command
      sleep 0.4
      @session.inspect.should == <<-EOS.gsub(/^ *\|/, '')
        |CommandRat::Session running: #{command}
        |  Received on standard output:
        |    one
        |  (No trailing newline, received EOF.)
        |  Received on standard error:
        |    two
        |  (Received trailing newline, no EOF.)
      EOS
    end
  end
end
