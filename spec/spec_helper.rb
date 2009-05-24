require 'spec'
require 'command_rat'
require 'fileutils'
require 'rbconfig'

module SpecHelper
  def self.included(mod)
    mod.before do
      @files_to_cleanup = []
    end

    mod.after do
      @files_to_cleanup.each do |name|
        FileUtils.rm_f name
      end
    end
  end

  def temp_dir
    File.dirname(__FILE__) + '/../tmp'
  end

  def clean_up(file_name)
    @files_to_cleanup << file_name
  end

  #
  # Create a temporary file and return its path.
  #
  def generate_file
    name = nil
    i = 1
    loop do
      name = "#{temp_dir}/#{i}"
      break if !File.exist?(name)
      i += 1
    end
    name = File.expand_path(name)
    FileUtils.touch name
    clean_up name
    name
  end

  #
  # Create a temporary executable with the given source, and return
  # the path.  Any '|'-delimited margin will be stripped first.
  #
  # The generated file will be cleaned up in the after hook.
  #
  def make_executable(source)
    source = source.gsub(/^ *\|/, '')
    name = generate_file
    open(name, 'w'){|f| f.print(source)}
    FileUtils.chmod(0755, name)
    name
  end

  #
  # Prefix the given source string with "#!/bin/sh" and make a
  # temporary executable out of it.
  #
  def make_shell_command(source)
    make_executable("#!/bin/sh\n" + source)
  end

  #
  # Prefix the given source string with a shebang line that launches
  # the current ruby interpreter, and make a temporary executable out
  # of it.
  #
  def make_ruby_command(source)
    ruby = File.join(Config::CONFIG['bindir'], Config::CONFIG['RUBY_INSTALL_NAME'])
    make_executable("#!#{ruby}\n" + source)
  end
end

Spec::Runner.configure do |config|
  config.include SpecHelper
  config.mock_with :mocha
end
