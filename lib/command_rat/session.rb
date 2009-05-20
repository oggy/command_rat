module CommandRat
  #
  # A session to run commands under.
  #
  #     app = CommandRat::Session.run('ruby', '-e', 'puts "hi"; STDERR.puts "eek!"') do |app|
  #       app.expect('Password: ')
  #       app.enter('wrong pass')
  #       app.expect('Bzzzt!', :on => :stderr)
  #     end
  #     app.exit_status.should != 0
  #
  class Session
    def initialize
      self.timeout = 5
      @env = ENV.to_hash
    end

    #
    # Create a CommandRat, and run the given command with it.
    #
    def self.run(*args, &block)
      new.run(*args, &block)
    end

    #
    # Run the given command.
    #
    def run(*command)
      wait_until_done if running?
      setup_environment
      begin
        @command = command.dup
        @status = nil
        @pid, @stdin, @stdout, @stderr = Open4.popen4(*command)
        @buffers = {@stdout => Buffer.new, @stderr => Buffer.new}
        @running = true
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
      @stdin.close
      read_until{@stdout.closed? && @stderr.closed?}
      pid, @status = Process::waitpid2(@pid)
      @pid = nil
    end

    #
    # Timeout (in seconds) when waiting for output.  Default is 5.
    #
    attr_accessor :timeout

    #
    # Environment variables available to the command.  Default is the
    # environment of the parent process when the Session is created.
    #
    attr_accessor :env

    #
    # The list of shell words of the last command run.
    #
    #     session = CommandRat::Session.new
    #     session.run 'echo', 'one', 'two'
    #     session.command  # ['echo', 'one', 'two']
    #
    attr_reader :command

    #
    # Wait until the given pattern (String or Regexp) occurs on the
    # target stream (standard output by default, see the :stream
    # option).  The output is consumed until the end of the pattern.
    #
    # Return the matched string, or raise Timeout if the timeout is
    # exceeded.
    #
    # Options:
    #
    # :on - Stream to read from (:stdout or :stderr). Default is
    #       :stdout.
    #
    def consume_to(pattern, options={})
      stream = stream_named(options[:on])
      buffer = buffer_for(stream)
      read_until(timeout) do
        match = buffer.advance_to(pattern) and
          return match
      end
    end

    #
    # Send the given string on standard input.
    #
    def input(string)
      @stdin.print string
    end

    #
    # Return all data that has been written to standard output by the
    # command.
    #
    def stdout
      wait_until_done
      return nil if @buffers.nil?
      buffer_for(@stdout).string
    end

    #
    # Return all data that has been written to standard error by the
    # command.
    #
    def stderr
      wait_until_done
      return nil if @buffers.nil?
      buffer_for(@stderr).string
    end

    #
    # Return the exit status of the last command that exited.
    #
    # If a command is still running, return nil.
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
    # Like #consume_to, but consume only the next line, and only match
    # +pattern+ in this line.
    #
    # Return the matched string, or raise Timeout if the timeout is
    # exceeded.
    #
    def output?(pattern, options={})
      line = next_line(options) or
        return false
      !!line.index(pattern)
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

    def stream_named(symbol)
      stream =
        case symbol
        when :stderr
          return @stderr
        when :stdout, nil
          return @stdout
        else
          raise ArgumentError, "invalid stream: #{symbol.inspect} (need :stderr or :stdout)"
        end
      return stream
    end

    def read_until(timeout=nil)
      timeout = 0.001 if timeout == 0  # select treats 0 as infinity
      start = Time.now
      loop do
        return if block_given? && yield

        open_streams = [@stdout, @stderr].reject{|s| s.closed?}
        return if open_streams.empty?

        stream_sets = IO.select(open_streams, [], [], timeout) or
          raise Timeout, "timeout exceeded"

        stream_sets[0].each do |stream|
          begin
            data = stream.read_nonblock(8192)
            buffer_for(stream) << data
          rescue EOFError
            stream.close
          end
        end
      end
    end

    def buffer_for(stream)
      @buffers[stream]
    end

    def raise_if_in_run_block(message)
      raise RunError, message if @in_run_block
    end

    def next_line(options={})
      stream = stream_named(options[:on] || :stdout)
      buffer = buffer_for(stream)
      read_until do
        match = buffer.advance_to(/.*?(\n|\r\n?)/) and
          return match[0]
      end
    end

    class Buffer
      def initialize
        @string = ''
        @cursor = 0
      end
      attr_accessor :string, :cursor

      def <<(string)
        @string << string
      end

      def advance_to(pattern)
        pattern = pattern.to_s unless pattern.is_a?(Regexp)
        index = @string.index(pattern, @cursor) or
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
    end
  end
end
