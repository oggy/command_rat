module CommandRat
  class Timeout < RuntimeError; end
  class RunError < RuntimeError; end
  class CommandNotFound < RuntimeError; end
end
