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

  def fix_arg_switch(sw0)
    pattern, conv = search_arg_switch_atype(sw0)
    Switch::SimpleArgument.new(pattern, conv, nil, nil, sw0.desc[0], sw0.desc[1..], sw0.block)
  end
  private :fix_arg_switch

  def make_switch(opts, block = nil)
    sw = super(opts, block || proc {})
    sw0 = sw[0]
    return sw if sw0.short || sw0.long

    sw0 = fix_arg_switch(sw0)
    long = sw0.arg.scan(/(?:\[\s*(.*?)\s*\]|(\S+))/).flatten.compact
    [sw0, nil, long]
  end

  def parse_arguments(argv) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    arg_sws = select { |sw| sw.is_a?(Switch::SimpleArgument) }
    return argv if arg_sws.empty?

    req_count, opt_count, rest_req_count, last_req_count =
      Switch::SimpleArgument.calc_argument_counts(arg_sws.map(&:ranges).flatten(1))

    argv_min = req_count + last_req_count + (rest_req_count || 0)
    raise MissingArgument, argv.join(' ').to_s if argv.size < argv_min

    argv_max = [rest_req_count ? Float::INFINITY : argv_min + opt_count, argv.size].min
    unless @commands.empty?
      index = argv[argv_min...argv_max].index { |arg| @commands.include?(arg) }
      argv_max = argv_min + index if index
    end

    arg_sws.each do |sw|
      conv = proc { |v| sw.send(:conv_arg, *sw.send(:parse_arg, v))[2] }
      a = sw.ranges.map do |r|
        if r.end.nil?
          argv_min -= r.begin
          rest_size = argv_max - argv_min
          argv_max = argv_min
          argv.slice!(0...rest_size).map(&conv)
        elsif r.begin.zero?
          next conv.call(nil) if argv_min == argv_max

          argv_max -= 1
          conv.call(argv.shift)
        else
          argv_min -= 1
          argv_max -= 1
          conv.call(argv.shift)
        end
      end
      sw.block.call(*a)
    end

    argv
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
    sw = @commands[name]
    return sw.block.call.send(block_given? ? :permute! : :order!, *args, **kwargs) if sw

    puts "#{program_name}:" \
         "'#{name}' is not a #{program_name} command. See '#{program_name} --help'."
    exit
  end

  def command(name, desc = nil, *args, &block)
    sw0 = Switch::SummarizeArgument.new(nil, nil, nil, nil, name.to_s, desc ? [desc] : [], nil) do
      self.class.new(desc, *args) do |opt|
        opt.program_name = "#{program_name} #{name}"
        block&.call(opt)
      end
    end
    top.append(sw0, nil, [sw0.arg])
    @commands[name.to_s] = sw0
    nil
  end

  class Switch < ::OptionParser::Switch
    class SummarizeArgument < NoArgument
      undef_method :add_banner

      def summarize(*args)
        original_arg = arg
        @short = arg.scan(/\[\s*.*?\s*\]|\S+/)
        @arg = nil
        res = super(*args)
        @arg = original_arg
        @short = nil
        res
      end

      def match_nonswitch?(*args)
        super(*args) if @pattern.is_a?(Regexp)
      end
    end

    class SimpleArgument < SummarizeArgument
      class << self
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

      def add_banner(to)
        to << " #{arg}"
      end
    end
  end
end
