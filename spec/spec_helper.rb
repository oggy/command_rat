require 'spec'
require 'command_rat'

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
  # Return a temp file name that does not yet exist.
  #
  def generate_file_name
    make_name = lambda{|i| "#{temp_dir}/#{i}"}
    i = 0
    name = make_name.call(0)
    while File.exist?(name)
      name = make_name.call(i += 1)
    end
    name
  end

  #
  # Create a temporary executable with the given source, and return
  # the path.  Any '|'-delimited margin will be stripped first.
  #
  # The generated file will be cleaned up in the after hook.
  #
  def make_executable(source)
    name = generate_file_name
    source = source.gsub(/^ *\|/, '')
    open(name, 'w'){|f| f.print(source)}
    clean_up name
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
end

Spec::Runner.configuration.include SpecHelper
