module CommandRat
  #
  # A session to run commands under.
  #
  #     app = CommandRat::Session.run('ruby', '-e', 'puts "hi"; STDERR.puts "eek!"')
  #     assert app.output?('Password: ')
  #     app.enter('wrong pass')
  #     assert app.output?('Bzzzt!', :on => :stderr)
  #     assert app.exit_status != 0
  #
  class Session
    def initialize
      self.timeout = 2
      @env = ENV.to_hash
    end

    #
    # Create a Session, and run the given command with it.  Return the
    # Session.
    #
    def self.run(*args, &block)
      new.run(*args, &block)
    end

    #
    # Run the given command.
    #
    # If a command is already running, wait for it to complete first.
    #
    def run(*command)
      wait_until_done if running?
      setup_environment
      begin
        @command = command.dup
        @status = nil
        @pid, @stdin, stdout, stderr = Open4.popen4(*command)
        @stdout = Stream.new(self, stdout)
        @stderr = Stream.new(self, stderr)
        self
      ensure
        teardown_environment
      end
    end

    #
    # True if the process is running, false otherwise.
    #
    def running?
      !!@pid
    end

    #
    # Reap the running process, if any.
    #
    def wait_until_done
      return if !running?
      close_input

      # TODO: handle case where command doesn't exit.
      start = Time.now
      @stdout.read_until_eof(timeout)
      @stderr.read_until_eof(timeout - (Time.now - start))
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
    # The last command run, as an array.
    #
    #     session = CommandRat::Session.new
    #     session.run 'echo', 'one', 'two'
    #     session.command  # ['echo', 'one', 'two']
    #
    attr_reader :command

    #
    # The standard output (as a CommandRat::Stream).
    #
    attr_reader :stdout

    #
    # The standard error (as a CommandRat::Stream).
    #
    attr_reader :stderr

    #
    # Send the given string on standard input.
    #
    def input(string)
      @stdin.print string
    end

    #
    # Close the standard input stream.
    #
    def close_input
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
    # Send the given string on standard input, appending a record
    # separator if necessary (like Kernel#puts).
    #
    def enter(line)
      @stdin.puts line
    end

    #
    # Return all data output on standard output (including consumed
    # data).
    #
    # Block until the command exits if necessary.
    #
    def standard_output
      wait_until_done
      @stdout.buffer.dup
    end

    #
    # Return all data output on standard output (including consumed
    # data).
    #
    # Block until the command exits if necessary.
    #
    def standard_error
      wait_until_done
      @stderr.buffer.dup
    end

    #
    # Return true if the given +string+ follows on standard output.
    #
    # Blocks until enough data is available, or EOF is encountered.
    #
    def output?(string)
      @stdout.next?(string)
    end

    #
    # Return true if the given +string+ follows on standard error.
    #
    # Blocks until enough data is available, or EOF is encountered.
    #
    def error?(string)
      @stderr.next?(string)
    end

    #
    # Return true if there is no more data on standard error.
    #
    # Blocks until enough data is available.
    #
    def no_more_output?
      @stdout.eof?
    end

    #
    # Return true if there is no more data on standard error.
    #
    # Blocks until enough data is available.
    #
    def no_more_error?
      @stderr.eof?
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

  class Stream
    def initialize(session, stream)
      @session = session
      @stream = stream
      @buffer = ''
      @cursor = 0
      @eof_found = false
    end

    #
    # The buffer of data fetched from the stream so far.
    #
    attr_reader :buffer

    #
    # The index of the next character to consume.
    #
    attr_reader :cursor

    #
    # Consume the next +n+ bytes, or as many as possible if EOF is
    # encountered before then.
    #
    def consume(n)
      target = @buffer.length + n
      read_until(@session.timeout) do
        @buffer.length == target || @eof
      end
    end

    #
    # Consume up to the end of +pattern+ (a String or Regexp).  Block
    # until the pattern appears, EOF is encountered, or the timeout
    # elapses.
    #
    # If a Regexp pattern is given, return the MatchData object of the
    # match, otherwise return the string matched.  If EOF is
    # encountered, return nil.  If the timeout is exceeded, raise
    # Timeout.
    #
    def consume_to(pattern)
      read_until(@session.timeout) do
        match = advance_to(pattern) and
          return match
      end
    end

    #
    # Return the next line of output.
    #
    # Block until the line is complete.  The line may be terminated by
    # a LF, CR, CRLF, or EOF.
    #
    def next_line(options={})
      match = consume_to(/(.*?)(?:\n|\r\n?)/) and
        return match[1]

      last_line = advance_to_end
      last_line.empty? ? nil : last_line
    end

    #
    # Return true if the given string follows, false otherwise.
    #
    # Block until enough data is available, or EOF is encountered.
    #
    def next?(string)
      read_until(@session.timeout) do
        @cursor + string.length <= @buffer.length || @eof_found
      end

      data = @buffer[@cursor, string.length]
      @cursor += data.length
      data == string
    end

    # (Private to Session.)  Read the remaining data into the buffer.
    def read_until_eof(timeout)  #:nodoc:
      read_until(timeout){@eof_found}
    end

    #
    # Return true if EOF has been reached.
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
        consume(1)
        @cursor == @buffer.length && @eof_found
      end
    end

    def inspect
      consumed, remaining = @buffer[0...@cursor], @buffer[@cursor..-1]
      consumed = consumed.inspect[1...-1]
      remaining = remaining.inspect[1...-1]
      "#<Stream: @#{@cursor} \e[1;30m#{consumed}\e[0m#{remaining}#{'$' if @eof_found}>"
    end

    private  # -------------------------------------------------------

    def <<(string)
      @buffer << string
    end

    def read_until(timeout)
      start = Time.now
      loop do
        return if block_given? && yield
        return if @eof_found

        # select treats 0 as infinity, so clamp it just above 0
        timeout_remaining = [timeout - (Time.now - start), 0.001].max
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

    def advance_to(pattern)
      pattern = pattern.to_s unless pattern.is_a?(Regexp)
      index = @buffer.index(pattern, @cursor) or
        return nil

      if pattern.is_a?(Regexp)
        match = Regexp.last_match
        @cursor = match.end(0)
        match
      else
        @cursor += pattern.length
        pattern.dup
      end
    end

    def advance_to_end
      rest = @buffer[@cursor..-1]
      @cursor = @buffer.length
      rest
    end
  end
end
