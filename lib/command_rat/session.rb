require 'shellwords'

module CommandRat
  #
  # A session to run commands under.
  #
  #     app = CommandRat::Session.run(%Q[ruby -e 'puts "hi"'])
  #     app.standard_output == "hi\n"
  #     app.exit_status == 0
  #
  class Session
    def initialize
      @timeout = 2
      @env = ENV.to_hash
    end

    #
    # Run the given command.
    #
    # If a command is already running, wait for it to complete first.
    #
    def run(command)
      wait_until_done if running?
      setup_environment
      begin
        @command = command.dup
        @status = nil
        words = Shellwords.shellwords(command)
        @pid, @stdin, stdout, stderr = Open4.popen4(*words)
        @standard_output = Stream.new(self, 'standard output', stdout)
        @standard_error = Stream.new(self, 'standard error' , stderr)
        self
      ensure
        teardown_environment
      end
    end

    #
    # True if a command is running, false otherwise.
    #
    def running?
      !!@pid
    end

    #
    # Reap the running process, if any.
    #
    def wait_until_done
      return if !running?
      send_eof

      # TODO: handle case where command doesn't exit.
      start = Time.now
      @standard_output.read_until_eof(timeout)
      @standard_error.read_until_eof(timeout - (Time.now - start))
      pid, @status = Process::waitpid2(@pid)
      @pid = nil
    end

    #
    # Timeout (in seconds) when waiting for output, or waiting for the
    # command to finish.  Default is 2.
    #
    attr_accessor :timeout

    #
    # Environment variables available to the command.  Default is the
    # process' environment when the Session is created.
    #
    attr_accessor :env

    #
    # The last command run.
    #
    #     session = CommandRat::Session.new
    #     session.run 'ls -l'
    #     session.command  # 'ls -l'
    #
    attr_reader :command

    #
    # The standard output (a CommandRat::Stream).
    #
    attr_reader :standard_output

    #
    # The standard error (a CommandRat::Stream).
    #
    attr_reader :standard_error

    #
    # Send the given string on standard input.
    #
    def send_input(string)
      @stdin.print string
    end

    #
    # Send EOF to the command on standard input.
    #
    def send_eof
      @stdin.close unless @stdin.closed?
    end

    #
    # Return the exit status of the command.
    #
    # Wait for the command to exit first if it's still running.
    #
    def exit_status
      wait_until_done
      @status && @status.exitstatus
    end

    #
    # Send the given string on standard input.
    #
    # A record separator is appended if necessary (like IO#puts), and
    # the stream cursors are advanced.
    #
    def enter(line)
      @standard_output.advance
      @standard_error.advance
      @stdin.puts line
    end

    #
    # Return a useful string for debugging.  Don't be afraid to #p out
    # a Session object.  (Not as painful as it sounds!)
    #
    def inspect
      string = "#{self.class} running: #{command}\n"
      string << @standard_output.inspect.gsub(/^/, '  ')
      string << @standard_error.inspect.gsub(/^/, '  ')
    end

    private  # -------------------------------------------------------

    def setup_environment
      # TODO: make this reentrant - fork another process?
      @original_environment = ENV.to_hash
      ENV.replace(env)
    end

    def teardown_environment
      ENV.replace(@original_environment)
      @original_environment = nil
    end
  end

  #
  # Wraps an output stream of the command under test.
  #
  # The stream is chunked into "responses."  The #cursor starts at the
  # beginning, and is moved to the end of the read input each time
  # #advance is called.  Methods like #== only look at data from the
  # cursor onwards.
  #
  # Normally, the Session advances the stream for you each time a user
  # action occurs (e.g., when a string is #enter-ed), but if you're
  # doing something tricky, you might want to #advance the Stream
  # yourself.
  #
  class Stream
    def initialize(session, name, stream)
      @session = session
      @name = name
      @stream = stream
      @buffer = ''
      @cursor = 0
      @eof_found = false
    end

    #
    # The associated session object.
    #
    attr_reader :session

    #
    # The human-readable name of the stream (e.g., "standard output").
    #
    attr_reader :name

    #
    # The buffer of data fetched from the stream so far.
    #
    attr_reader :buffer

    #
    # The index in the buffer that current response starts from.
    #
    attr_reader :cursor

    #
    # Return all data currently available from the cursor onwards.
    #
    # Note that this does not block.  If you want to test the data on
    # the stream, use #== or #include? instead.
    #
    def response
      buffer_available_data
      @buffer[@cursor..-1]
    end

    #
    # Return true if the given string appears on the stream after the
    # cursor.  Wait until the configured timeout if necessary.
    #
    def include?(string)
      read_until{response.include?(string)} || false
    rescue Timeout
      false
    end

    #
    # Return true if the stream contains exactly the given string at
    # the cursor.  Wait until the configured timeout if necessary.
    #
    # TODO: At the moment, this just checks that the output starts
    # with the given string.  We need to check that there is nothing
    # between this and the next user action too.
    #
    def ==(string)
      read_until{@buffer.length >= @cursor + string.length}
      response == string
    rescue Timeout
      false
    end

    #
    # Move the cursor to the end of the available input.
    #
    def advance
      buffer_available_data
      @cursor = @buffer.length
    end

    #
    # Return true if EOF has been reached, and all data has been
    # consumed.
    #
    # Blocks until EOF is encountered if necessary.
    #
    def eof?
      if @cursor < @buffer.length
        false
      elsif @eof_found
        true
      else
        # We're at the end of the buffer, but haven't got EOF yet.
        read_bytes(1)
        @cursor == @buffer.length && @eof_found
      end
    end

    #
    # Return true if EOF has been found, even if we haven't advanced
    # to the end yet.
    #
    def eof_found?
      @eof_found
    end

    def inspect
      buffer_available_data
      string = "Received on #{name}:\n"
      string << response.gsub(/^/, '  ')
      string << "\n" unless string[-1] == ?\n
      newline_indicator = buffer[-1] == ?\n ? 'Received' : 'No'
      eof_indicator = eof_found? ? 'received' : 'no'
      string << "(#{newline_indicator} trailing newline, #{eof_indicator} EOF.)\n"
    end

    # (Private to Session.)  Read the remaining data into the buffer.
    def read_until_eof(timeout)  #:nodoc:
      read_until(timeout){@eof_found}
    end

    private  # -------------------------------------------------------

    def buffer_available_data
      read_until(0)
    rescue Timeout
    end

    #
    # Read from the stream until either:
    #
    #  * The given block returns true, in which case return the value
    #    yielded by the block.  The block will be called once before
    #    any data is read, and once after each block of data read.
    #  * EOF is reached, in which case return nil.
    #  * The given timeout elapses, in which case raise a Timeout.
    #
    def read_until(timeout=@session.timeout)
      start = Time.now
      loop do
        if block_given?
          result = yield and
            return result
        end

        return if @eof_found

        # select treats 0 as infinity, so clamp it just above 0
        timeout_remaining = [timeout - (Time.now - start), 0.00001].max
        IO.select([@stream], [], [], timeout_remaining) or
          raise Timeout, "timeout exceeded"

        read_chunk
      end
    end

    def read_chunk
      @buffer << @stream.read_nonblock(8192)
    rescue EOFError
      @stream.close
      @eof_found = true
    end

    def read_bytes(n)
      target = @buffer.length + n
      read_until{@buffer.length >= target}
    end
  end
end
