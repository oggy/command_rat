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
    # This resets the output streams.
    #
    def run(*command)
      @command = command.dup
      command[0] = File.expand_path(command[0])
      @status = Open4.popen4(*command) do |pid, @stdin, @stdout, @stderr|
        @status = nil
        @buffers = {@stdout => '', @stderr => ''}
        if block_given?
          @in_run_block = true
          begin
            yield self
          ensure
            @in_run_block = false
          end
        end
        @stdin.close
        read_until{@stdout.closed? && @stderr.closed?}
      end
      self
    end

    #
    # The Process::Status of the last command run.
    #
    attr_reader :command

    #
    # Timeout (in seconds) when waiting for output.
    #
    attr_accessor :timeout

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
    def consume(pattern, options={})
      stream = stream_named(options[:on])
      buffer = buffer_for(stream)
      read_until(timeout) do
        pattern = pattern.to_s unless pattern.is_a?(Regexp)
        slice = buffer.slice!(pattern) and
          return pattern.is_a?(Regexp) ? Regexp.last_match : slice
      end
    end

    #
    # Like #consume, but consume only the next line, and only match
    # +pattern+ in this line.
    #
    # Return the matched string, or raise Timeout if the timeout is
    # exceeded.
    #
    def expect(pattern, options={})
      result = consume(/.*?(\n|\r\n?)/, options) or
        return result
      line = result[0]
      if pattern.is_a?(Regexp)
        line.match(pattern)
      else
        line[pattern]
      end
    end

    #
    # Send the given string on standard input.
    #
    def input(string)
      @stdin.print string
    end

    #
    # Send the given string on standard input, appending a record
    # separator if necessary (like Kernel#puts).
    #
    def enter(line)
      @stdin.puts line
    end

    #
    # Return the standard output of the program, minus anything that
    # has been consumed.
    #
    # Raise a RunError if in a run block.  Use #consume to check the
    # output for a program while it's still running instead.
    #
    def stdout
      raise_if_in_run_block "don't use #stdout in a #run block - try #consume instead"
      read_until(0)
      buffer_for(@stdout)
    end

    #
    # Return the standard error of the program, minus anything that
    # has been consumed.
    #
    # Raise a RunError if in a run block.  Use #consume to check the
    # output for a program while it's still running instead.
    #
    def stderr
      raise_if_in_run_block "don't use #stdout in a #run block - try #consume(pattern, :on => :stderr) instead"
      read_until(0)
      buffer_for(@stderr)
    end

    #
    # Return the exit status of the last command run.
    #
    # If the command is still running, return nil.
    #
    def exit_status
      raise_if_in_run_block "don't use #exit_status in a #run block - wait until the block is complete"
      @status && @status.exitstatus
    end

    private  # -------------------------------------------------------

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

        return if block_given? && yield
      end
    end

    def buffer_for(stream)
      @buffers[stream]
    end

    def raise_if_in_run_block(message)
      raise RunError, message if @in_run_block
    end
  end
end
