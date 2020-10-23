# frozen_string_literal: true

require 'xoptparse/version'
require 'optparse'

class XOptionParser < ::OptionParser
  def initialize(description = nil, *args, &block)
    @commands = {}
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

  def select(*args, &block)
    Enumerator.new do |y|
      visit(:each_option) { |el| y << el }
    end.select(*args, &block)
  end
  private :select

  def no_options
    select { |sw| sw.is_a?(::OptionParser::Switch) }.all? { |sw| !(sw.short || sw.long) }
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

  def search_arg_switch_atype(sw0)
    visit(:tap) do |el|
      el.atype.each do |klass, atype|
        next unless atype[1] == sw0.conv
        return [nil, nil] if klass == Object

        return atype
      end
    end

    [nil, nil]
  end
  private :search_arg_switch_atype

  def fix_arg_switch(sw0) # rubocop:disable Metrics/AbcSize
    if !(sw0.short || sw0.long)
      pattern, conv = search_arg_switch_atype(sw0)
      Switch::SimpleArgument.new(pattern, conv, nil, nil, sw0.desc[0], sw0.desc[1..], sw0.block)
    elsif sw0.is_a?(Switch::PlacedArgument) && sw0.long.size == 1 && /^--\[no-\]/ =~ sw0.long.first
      args = [sw0.pattern, sw0.conv, sw0.short, sw0.long, sw0.arg, sw0.desc, sw0.block]
      Switch::FlagArgument.new(*args)
    else
      sw0
    end
  end
  private :fix_arg_switch

  def make_switch(opts, block = nil)
    sw = super(opts, block || proc {})
    sw0 = sw[0] = fix_arg_switch(sw[0])
    return sw if sw0.short || sw0.long

    long = sw0.arg_parameters.map(&:first)
    [sw0, nil, long]
  end

  def parse_arguments(argv, setter = nil, opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    arg_sws = select { |sw| sw.is_a?(Switch::SummarizeArgument) && !opts.include?(sw.switch_name) }
    return argv if arg_sws.empty?

    sws_ranges = arg_sws.map(&:ranges).flatten(1)
    req_count = sws_ranges.sum(&:begin)
    opt_count = sws_ranges.sum(&:size) - sws_ranges.size
    opt_index = argv[req_count...].index { |arg| @commands.include?(arg) } unless @commands.empty?
    opt_count = [opt_count, opt_index || Float::INFINITY, argv.size - req_count].min

    arg_sws.each_with_index do |sw, i|
      if sw.is_a?(Switch::SimpleArgument)
        callable = false
        conv = proc do |v|
          callable = true
          sw.send(:conv_arg, *sw.send(:parse_arg, v))[2]
        end
        a = sw.ranges.map do |r|
          raise MissingArgument if r.begin.positive? && argv.empty?

          if r.end.nil?
            rest_size = r.begin + opt_count
            req_count -= r.begin
            opt_count = 0
            argv.slice!(0...rest_size).map(&conv)
          elsif r.begin.positive?
            req_count -= 1
            conv.call(argv.shift)
          elsif opt_count.positive?
            opt_count -= 1
            conv.call(argv.shift)
          end
        end
        if callable
          val = sw.block.call(*a)
          setter&.call(sw.switch_name, val)
        end
      elsif sw.pattern =~ argv.first
        argv.shift
        @command_switch = sw
        break
      elsif !argv.empty? && i == arg_sws.size - 1
        raise MissingArgument
      end
    end

    argv
  end
  private :parse_arguments

  def parse_in_order(argv = default_argv, setter = nil, &nonopt)
    nonopts = []
    opts = {}
    opts_setter = proc do |name, val|
      opts[name] = true
      setter&.call(name, val)
    end
    rest = if nonopt
             super(argv, opts_setter, &nonopts.method(:<<))
           else
             nonopts = super(argv, opts_setter)
           end
    parse_arguments(nonopts, setter, opts).map(&nonopt)
    rest
  end
  private :parse_in_order

  def order!(*args, into: nil, **kwargs)
    return super(*args, into: into, **kwargs) if @commands.empty?

    @command_switch = nil
    argv = super(*args, into: into, **kwargs, &nil)
    return argv unless @command_switch

    into = into[@command_switch.arg.to_sym] = {} if into
    @command_switch.block.call.send(block_given? ? :permute! : :order!, *args, into: into, **kwargs)
  end

  def command(name, desc = nil, *args, &block)
    name = name.to_s
    pattern = /^#{name.gsub('_', '[-_]?')}$/i
    sw0 = Switch::SummarizeArgument.new(pattern, nil, nil, nil, name, desc ? [desc] : [], nil) do
      self.class.new(desc, *args) do |opt|
        opt.program_name = "#{program_name} #{name}"
        block&.call(opt)
      end
    end
    top.append(sw0, nil, [sw0.arg])
    @commands[name] = sw0
    nil
  end

  class Switch < ::OptionParser::Switch
    class SummarizeArgument < self
      undef_method :add_banner

      attr_reader :ranges
      attr_reader :arg_parameters

      def initialize(*)
        super
        @ranges = []
        @arg_parameters = arg.scan(/\[\s*(.*?)\s*\]|(\S+)/).map do |opt, req|
          name = opt || req
          [name.sub(/\s*\.\.\.$/, ''), opt ? :opt : :req, name.end_with?('...') ? :rest : nil]
        end
      end

      def summarize(*)
        original_arg = arg
        @short = arg_parameters.map do |name, type, rest|
          var = "#{name}#{rest ? '...' : ''}"
          type == :req ? var : "[#{var}]"
        end
        @arg = nil
        res = super
        @arg = original_arg
        @short = nil
        res
      end

      def match_nonswitch?(*)
        nil
      end

      def switch_name
        arg_parameters.first.first
      end

      def parse(_arg, _argv)
        raise XOptionParser::InvalidOption
      end
    end

    class SimpleArgument < SummarizeArgument
      def initialize(*)
        super
        @ranges = arg_parameters.map do |_name, type, rest|
          (type == :req ? 1 : 0)..(rest == :rest ? nil : 1)
        end
      end

      def add_banner(to)
        to << " #{arg}"
      end

      def parse(arg, argv) # rubocop:disable Metrics/CyclomaticComplexity
        case ranges.size
        when 0
          yield(NeedlessArgument, arg) if arg
          conv_arg(arg)
        when 1
          unless arg
            raise XOptionParser::MissingArgument if argv.empty?

            arg = argv.shift
          end
          arg = [arg] if ranges.first.end.nil?
          conv_arg(*parse_arg(arg, &method(:raise)))
        else
          super(arg, argv)
        end
      end
    end

    class FlagArgument < PlacedArgument
      def parse(arg, argv, &error)
        super(arg, argv, &error).tap do |val|
          raise OptionParser::InvalidArgument if val[0].nil? && val[2].nil?
        end
      rescue OptionParser::InvalidArgument
        conv_arg(arg)
      end
    end
  end
end
