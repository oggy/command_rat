require 'spec/spec_helper'
require 'fileutils'

describe "CommandRat::Session" do
  before do
    @session = CommandRat::Session.new
  end

  after do
    @session.timeout = 2  # some specs shorten this
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
      @session.standard_output == "xx:yy:"
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

  describe "#standard_output" do
    it "should be nil before any commands are run" do
      @session.standard_output.should be_nil
    end

    it "should return the standard output stream" do
      command = make_shell_command('echo out; echo err >&2')
      @session.run command
      @session.standard_output.should be_a(CommandRat::Stream)
      @session.standard_output.buffer == "out\n"
    end
  end

  describe "#standard_error" do
    it "should be nil before any commands are run" do
      @session.standard_error.should be_nil
    end

    it "should return the standard error stream" do
      command = make_shell_command('echo out; echo err >&2')
      @session.run command
      @session.standard_error.should be_a(CommandRat::Stream)
      @session.standard_error.buffer == "err\n"
    end
  end

  describe "#send_input" do
    it "should send the given string on standard input" do
      command = make_shell_command('cat <&0')
      @session.run command
      @session.send_input "hi"
      @session.wait_until_done
      @session.standard_output.buffer.should == "hi"
    end
  end

  describe "#exit_status" do
    it "should be nil before any commands are run" do
      @session.exit_status.should be_nil
    end

    it "should be nil after the command is run, but before it has exited" do
      command = make_shell_command('')
      @session.exit_status.should be_nil
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
      @session.standard_output.buffer.should == "hi#$/"
    end

    it "should advance the cursors" do
      command = make_shell_command('echo a; echo bb >&2; read x')
      @session.run command
      sleep 0.2
      @session.standard_output.cursor.should == 0
      @session.standard_error.cursor.should == 0
      @session.enter "hi"
      @session.standard_output.cursor.should == 2
      @session.standard_error.cursor.should == 3
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

  describe "Stream" do
    describe "#response" do
      it "should return everything after the cursor so far received" do
        command = make_shell_command('echo ab')
        @session.run command
        @session.wait_until_done
        @session.standard_output.advance_by 1
        @session.standard_output.response.should == "b\n"
      end
    end

    describe "#include?" do
      it "should return true if the given string appears after the cursor" do
        command = make_shell_command('echo one')
        @session.run command
        @session.wait_until_done
        @session.standard_output.include?('one').should be_true
      end

      it "should return false if the given string does not appear at all" do
        command = make_shell_command('echo one')
        @session.run command
        @session.wait_until_done
        @session.standard_output.include?('two').should be_false
      end

      it "should return false if the given string only appears before the cursor" do
        command = make_shell_command('echo ab')
        @session.run command
        @session.standard_output.include?('a').should be_true
        @session.standard_output.advance_by 1
        @session.standard_output.include?('a').should be_false
      end

      it "should wait until the configured timeout if necessary" do
        command = make_shell_command('sleep 0.2; echo one')
        @session.run command
        @session.standard_output.include?('one')
      end

      it "should return false if the configured timeout elapses before the given string appears" do
        command = make_shell_command('sleep 0.4; echo one')
        @session.timeout = 0.2
        @session.run command
        @session.standard_output.include?('one').should be_false
      end

      it "should not advance the cursor" do
        command = make_shell_command('echo a; echo b')
        @session.run command
        @session.standard_output.include?('a').should be_true
        @session.standard_output.cursor.should == 0
      end
    end

    describe "#==" do
      it "should return true if the given string appears immediately after the cursor" do
        command = make_shell_command('echo ab')
        @session.run command
        @session.wait_until_done
        @session.standard_output.advance_by 1
        @session.standard_output.==("b\n").should be_true
      end

      it "should return false if the given string appears after the cursor, but not immediately after" do
        command = make_shell_command('echo abc')
        @session.run command
        @session.wait_until_done
        @session.standard_output.advance_by 1
        @session.standard_output.==("c\n").should be_false
      end

      it "should return false if the given string only appears before the cursor" do
        command = make_shell_command('echo ab')
        @session.run command
        @session.wait_until_done
        @session.standard_output.advance_by 1
        @session.standard_output.==("ab\n").should be_false
      end

      it "should wait until the configured timeout if necessary" do
        command = make_shell_command('sleep 0.2; echo one')
        @session.run command
        @session.standard_output.==("one\n").should be_true
      end

      it "should not wait for the timeout if it's not necessary" do
        command = make_shell_command('echo one; sleep 0.4')
        @session.run command
        lambda{timeout(0.2){@session.standard_output.==("one\n")}}.should_not raise_error
      end

      it "should return false if the configured timeout elapses before the given string appears" do
        command = make_shell_command('sleep 0.4; echo one')
        @session.timeout = 0.2
        @session.run command
        @session.standard_output.==("one\n").should be_false
      end

      it "should not advance the cursor" do
        command = make_shell_command('echo one')
        @session.run command
        @session.standard_output.==("one\n").should be_true
        @session.standard_output.cursor.should == 0
      end
    end

    describe "#next?" do
      it "should return true if the given string appears immediately after the cursor" do
        command = make_shell_command('echo ab')
        @session.run command
        @session.wait_until_done
        @session.standard_output.advance_by 1
        @session.standard_output.next?("b\n").should be_true
      end

      it "should return false if the given string appears after the cursor, but not immediately after" do
        command = make_shell_command('echo abc')
        @session.run command
        @session.wait_until_done
        @session.standard_output.advance_by 1
        @session.standard_output.next?("c\n").should be_false
      end

      it "should return false if the given string only appears before the cursor" do
        command = make_shell_command('echo ab')
        @session.run command
        @session.wait_until_done
        @session.standard_output.advance_by 1
        @session.standard_output.next?("ab\n").should be_false
      end

      it "should wait until the configured timeout if necessary" do
        command = make_shell_command('sleep 0.2; echo one')
        @session.run command
        @session.standard_output.next?("one\n").should be_true
      end

      it "should not wait for the timeout if it's not necessary" do
        command = make_shell_command('echo one; sleep 0.4')
        @session.run command
        lambda{timeout(0.2){@session.standard_output.next?("one\n")}}.should_not raise_error
      end

      it "should return false if the configured timeout elapses before the given string appears" do
        command = make_shell_command('sleep 0.4; echo one')
        @session.timeout = 0.2
        @session.run command
        @session.standard_output.next?("one\n").should be_false
      end

      it "should advance the cursor if the given string follows" do
        command = make_shell_command('echo one')
        @session.run command
        @session.standard_output.next?("one\n").should be_true
        @session.standard_output.cursor.should == 4
      end

      it "should not advance the cursor if the given string follows" do
        command = make_shell_command('echo one')
        @session.run command
        @session.standard_output.next?("x\n").should be_false
        @session.standard_output.cursor.should == 0
      end
    end

    describe "#advance" do
      it "should move the cursor to the end of the buffered data" do
        command = make_shell_command('echo one; echo two; sleep 0.4; echo three')
        @session.run command
        sleep 0.2
        @session.standard_output.advance
        sleep 0.4
        @session.standard_output.response.should == "three\n"
      end
    end

    describe "#advance_by" do
      it "should move the cursor forward by the given number of characters" do
        command = make_shell_command('echo ab')
        @session.run command
        @session.standard_output.advance_by 1
        @session.standard_output.cursor.should == 1
        @session.standard_output.advance_by 1
        @session.standard_output.cursor.should == 2
      end

      it "should wait until the given number of characters is available" do
        command = make_shell_command('sleep 0.2; echo a')
        @session.run command
        @session.standard_output.advance_by 2
        @session.standard_output.buffer.should == "a\n"
      end

      it "should raise a Timeout if the configured timeout is exceeded" do
        command = make_shell_command('sleep 0.4; echo a')
        @session.timeout = 0.2
        @session.run command
        lambda{@session.standard_output.advance_by 2}.should raise_error(CommandRat::Timeout)
      end

      it "should raise IndexError if EOF is received before the given number of characters is encoutered" do
        command = make_shell_command('')
        @session.run command
        lambda{@session.standard_output.advance_by 1}.should raise_error(IndexError)
      end
    end

    describe "#eof?" do
      it "should return true if EOF has been encountered" do
        command = make_shell_command('')
        @session.run command
        @session.wait_until_done
        @session.standard_output.eof?.should be_true
      end

      it "should return false if there is more data already available" do
        command = make_shell_command('echo x')
        @session.run command
        @session.wait_until_done
        @session.standard_output.eof?.should be_false
      end

      it "should return false if there is more data, but it has not come in yet" do
        command = make_shell_command('sleep 0.1; echo x')
        @session.run command
        @session.standard_output.eof?.should be_false
      end

      it "should return true if we're at the end of the file, but the EOF has not come in yet" do
        command = make_shell_command('sleep 0.1')
        @session.run command
        @session.standard_output.eof?.should be_true
      end

      it "should raise a Timeout if there is no more data available, but the EOF doesn't come in before the timeout" do
        command = make_shell_command('sleep 0.4')
        @session.timeout = 0.2
        @session.run command
        lambda{@session.standard_output.eof?}.should raise_error(CommandRat::Timeout)
      end
    end
  end
end
