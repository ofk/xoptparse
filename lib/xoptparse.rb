# frozen_string_literal: true

require 'xoptparse/version'
require 'optparse'

class XOptionParser < ::OptionParser
  def initialize(*args)
    @commands = {}
    super(*args)
  end

  def order!(*args, **kwargs)
    return super(*args, **kwargs) if @commands.empty?

    argv = super(*args, **kwargs) { |a| throw :terminate, a }
    return argv if argv.empty?

    name = argv.shift
    command = @commands[name]
    return command.call.send(block_given? ? :permute! : :order!, *args, **kwargs) if command

    puts "#{program_name}:" \
         "'#{name}' is not a #{program_name} command. See '#{program_name} --help'."
    exit
  end

  def command(name, *args, &block)
    @commands[name.to_s] = proc do
      self.class.new(*args, &block)
    end
    nil
  end
end
