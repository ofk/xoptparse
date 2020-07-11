# frozen_string_literal: true

require 'xoptparse/version'
require 'optparse'

class XOptionParser < ::OptionParser
  def initialize(*args)
    @commands = {}
    super(*args)
  end

  def define_at(target, *opts, &block)
    sw = make_switch(opts, block)
    case target
    when :tail
      base.append(*sw)
    when :head
      top.prepend(*sw)
    else
      top.append(*sw)
    end
    sw[0]
  end
  private :define_at

  def define(*args, &block)
    define_at(:body, *args, &block)
  end
  alias def_option define

  def define_head(*args, &block)
    define_at(:head, *args, &block)
  end
  alias def_head_option define_head

  def define_tail(*args, &block)
    define_at(:tail, *args, &block)
  end
  alias def_tail_option define_tail

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
