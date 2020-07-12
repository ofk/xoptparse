# frozen_string_literal: true

require 'xoptparse/version'
require 'optparse'

class XOptionParser < ::OptionParser
  def initialize(description = nil, *args, &block)
    @commands = {}
    @arg_stack = [[], []]
    @banner_usage = 'Usage: '
    @banner_options = '[options]'
    @banner_command = '<command>'
    super(nil, *args) do |opt|
      if description
        opt.separator ''
        opt.separator description
      end
      block&.call(opt)
    end
  end

  def no_options
    visit(:each_option) do |sw0|
      next unless sw0.is_a?(::OptionParser::Switch)
      return false if sw0.short || sw0.long
    end
    true
  end
  private :no_options

  def banner
    return @banner if @banner

    banner = +"#{@banner_usage}#{program_name}"
    banner << " #{@banner_options}" unless no_options
    visit(:add_banner, banner)
    banner << " #{@banner_command}" unless @commands.empty?

    banner
  end

  def summarize(to = [], width = @summary_width, max = width - 1, indent = @summary_indent, &blk)
    nl = "\n"
    blk ||= proc { |l| to << (l.index(nl, -1) ? l : l + nl) }

    res = super(to, width, max, indent, &blk)

    unless @commands.empty?
      @commands.each do |name, command|
        sw = Switch::NoArgument.new(nil, nil, [name], nil, nil, command[1] ? [command[1]] : [], nil)
        sw.summarize({}, {}, width, max, indent, &blk)
      end
    end

    res
  end

  def define_opt_switch_values(target, swvs)
    case target
    when :tail
      base.append(*swvs)
    when :head
      top.prepend(*swvs)
    else
      top.append(*swvs)
    end
  end
  private :define_opt_switch_values

  def search_arg_switch_atype(sw0)
    @stack.reverse_each do |el|
      el.atype.each do |klass, atype|
        next unless atype[1] == sw0.conv
        return [nil, nil] if klass == Object

        return atype
      end
    end

    [nil, nil]
  end
  private :search_arg_switch_atype

  def fix_arg_switch(sw0)
    pattern, conv = search_arg_switch_atype(sw0)
    Switch::SimpleArgument.new(pattern, conv, nil, nil, sw0.desc[0], sw0.desc[1..], sw0.block)
  end
  private :fix_arg_switch

  def valid_arg_switch(sw0)
    ranges = @arg_stack.flatten(1).map(&:ranges).flatten(1)
    unless Switch::SimpleArgument.valid_ranges?(ranges)
      raise ArgumentError, "unsupported argument format: #{sw0.arg.inspect}"
    end

    sw0
  end
  private :valid_arg_switch

  def define_arg_switch(target, sw0)
    case target
    when :tail
      @arg_stack[1].append(sw0)
    when :head
      @arg_stack[0].prepend(sw0)
    else
      @arg_stack[0].append(sw0)
    end

    valid_arg_switch(sw0)
  end
  private :define_arg_switch

  def define_at(target, *opts, &block)
    sw = make_switch(opts, block || proc {})
    sw0 = sw[0]
    if sw0.short || sw0.long
      define_opt_switch_values(target, sw)
    else
      sw0 = fix_arg_switch(sw0)
      define_arg_switch(target, sw0)
      long = sw0.arg.scan(/(?:\[\s*(.*?)\s*\]|(\S+))/).flatten.compact
      define_opt_switch_values(target, [sw0, nil, long])
    end
    sw0
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

  def parse_arguments(original_argv) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    arg_sws = @arg_stack.flatten(1)
    return original_argv if arg_sws.empty?

    req_count, opt_count, rest_req_count, last_req_count =
      Switch::SimpleArgument.calc_argument_counts(arg_sws.map(&:ranges).flatten(1))

    argv_min = req_count + last_req_count + (rest_req_count || 0)
    raise MissingArgument, original_argv.join(' ').to_s if original_argv.size < argv_min

    argv_max = rest_req_count ? nil : argv_min + opt_count
    unless @commands.empty?
      index = original_argv[argv_min...argv_max].index { |arg| @commands.include?(arg) }
      argv_max = argv_min + index if index
    end

    argv = original_argv.slice!(0...argv_max)

    opt_size = [argv.size - argv_min, opt_count].min
    req_argv = argv[0...req_count] + argv[(argv.size - last_req_count)...argv.size]
    opt_argv = argv[req_count...(req_count + opt_size)] # + ([nil] * (opt_count - opt_size))
    rest_argv = argv[(req_count + opt_size)...(argv.size - last_req_count)]

    arg_sws.each do |sw|
      conv = proc { |v| sw.send(:conv_arg, *sw.send(:parse_arg, v))[2] }
      a = sw.ranges.map do |r|
        if r.end.nil?
          rest_argv.map(&conv)
        elsif r.begin.zero?
          conv.call(opt_argv.shift)
        else
          conv.call(req_argv.shift)
        end
      end
      sw.block.call(*a)
    end

    original_argv
  end
  private :parse_arguments

  def parse_in_order(*args, &nonopt)
    argv = []
    rest = if nonopt
             super(*args, &argv.method(:<<))
           else
             argv = super(*args)
           end
    parse_arguments(argv).map(&nonopt)
    rest
  end
  private :parse_in_order

  def order!(*args, **kwargs)
    return super(*args, **kwargs) if @commands.empty?

    argv = super(*args, **kwargs, &nil)
    return argv if argv.empty?

    name = argv.shift
    cmd = @commands[name]
    return cmd.first.call.send(block_given? ? :permute! : :order!, *args, **kwargs) if cmd

    puts "#{program_name}:" \
         "'#{name}' is not a #{program_name} command. See '#{program_name} --help'."
    exit
  end

  def command(name, desc = nil, *args, &block)
    @commands[name.to_s] = [proc do
      self.class.new(desc, *args) do |opt|
        opt.program_name = "#{program_name} #{name}"
        block.call(opt) if block
      end
    end, desc]
    nil
  end

  class Switch < ::OptionParser::Switch
    class SimpleArgument < NoArgument
      class << self
        def valid_ranges?(ranges)
          ranges.inject(0) do |pt, r| # prev_type = req: 0, opt: 1, rest: 2, after_req: 3
            t = r.end.nil? ? 2 : 1 - r.begin
            next pt.zero? ? 0 : 3 if t.zero?
            next t if pt < 2 && pt <= t

            return false
          end
          true
        end

        def calc_argument_counts(ranges)
          req_count = 0
          opt_count = 0
          rest_req_count = nil
          last_req_count = 0
          ranges.each do |r|
            if r.end.nil?
              rest_req_count = r.begin
            elsif r.begin.zero?
              opt_count += 1
            elsif opt_count.positive? || rest_req_count
              last_req_count += 1
            else
              req_count += 1
            end
          end
          [req_count, opt_count, rest_req_count, last_req_count]
        end
      end

      attr_reader :ranges

      def initialize(*args)
        super(*args)
        @ranges = arg.scan(/\[\s*(.*?)\s*\]|(\S+)/).map do |opt, req|
          (opt ? 0 : 1)..((opt || req).end_with?('...') ? nil : 1)
        end
      end

      def summarize(*args)
        original_arg = arg
        @short = arg.scan(/\[\s*.*?\s*\]|\S+/)
        @arg = nil
        res = super(*args)
        @arg = original_arg
        @short = nil
        res
      end

      def add_banner(to)
        to << " #{arg}"
      end

      def match_nonswitch?(*args)
        super(*args) if @pattern.is_a?(Regexp)
      end
    end
  end
end
