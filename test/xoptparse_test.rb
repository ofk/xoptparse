# frozen_string_literal: true

require 'test_helper'

class XOptionParserTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute { ::XOptionParser::VERSION.nil? }
  end

  def test_parse
    create_option_parser = proc do |res|
      XOptionParser.new do |o|
        o.on('-o') { res[:o] = true }
      end
    end

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!([])
    assert { argv.empty? }
    assert { res == {} }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o])
    assert { argv.empty? }
    assert { res == { o: true } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o v])
    assert { argv == %w[v] }
    assert { res == { o: true } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[v -o])
    assert { argv == %w[v] }
    assert { res == { o: true } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[v])
    assert { argv == %w[v] }
    assert { res == {} }
  end

  def test_sub_command
    create_option_parser = proc do |res|
      XOptionParser.new do |o|
        res[:c] = :root
        res[:o] = nil
        o.on('-o') { res[:o] = :root }
        o.command('foo') do |o2|
          res[:c] = :foo
          o2.on('-o') { res[:o] = :foo }
          o2.command('hoge') do |o3|
            res[:c] = :hoge
            o3.on('-o') { res[:o] = :hoge }
          end
        end
        o.command('bar') do
          res[:c] = :bar
        end
      end
    end

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!([])
    assert { argv.empty? }
    assert { res == { c: :root, o: nil } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o])
    assert { argv.empty? }
    assert { res == { c: :root, o: :root } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o foo])
    assert { argv.empty? }
    assert { res == { c: :foo, o: :root } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo])
    assert { argv.empty? }
    assert { res == { c: :foo, o: nil } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo -o])
    assert { argv.empty? }
    assert { res == { c: :foo, o: :foo } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo -o hoge])
    assert { argv.empty? }
    assert { res == { c: :hoge, o: :foo } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo hoge -o])
    assert { argv.empty? }
    assert { res == { c: :hoge, o: :hoge } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo hoge fuga])
    assert { argv == %w[fuga] }
    assert { res == { c: :hoge, o: nil } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[bar])
    assert { argv.empty? }
    assert { res == { c: :bar, o: nil } }
  end
end
