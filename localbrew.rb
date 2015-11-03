#!/System/Library/Frameworks/Ruby.framework/Versions/Current/usr/bin/ruby
HOMEBREW_PREFIX = '.localbrew'
HOMEBREW_CACHE = '/Library/Caches/Homebrew'
HOMEBREW_REPO = 'https://github.com/Homebrew/homebrew'

module Tty extend self
  def blue; bold 34; end
  def white; bold 39; end
  def red; underline 31; end
  def reset; escape 0; end
  def bold n; escape "1;#{n}" end
  def underline n; escape "4;#{n}" end
  def escape n; "\033[#{n}m" if STDOUT.tty? end
end

class Array
  def shell_s
    cp = dup
    first = cp.shift
    cp.map{ |arg| arg.gsub " ", "\\ " }.unshift(first) * " "
  end
end

def ohai *args
  puts "#{Tty.blue}==>#{Tty.white} #{args.shell_s}#{Tty.reset}"
end

def warn warning
  puts "#{Tty.red}Warning#{Tty.reset}: #{warning.chomp}"
end

def system *args
  abort "Failed during: #{args.shell_s}" unless Kernel.system(*args)
end

def sudo *args
  ohai "/usr/bin/sudo", *args
  system "/usr/bin/sudo", *args
end

def getc  # NOTE only tested on OS X
  system "/bin/stty raw -echo"
  if STDIN.respond_to?(:getbyte)
    STDIN.getbyte
  else
    STDIN.getc
  end
ensure
  system "/bin/stty -raw echo"
end

def wait_for_user
  puts
  puts "Press RETURN to continue or any other key to abort"
  c = getc
  # we test for \r and \n because some stuff does \r instead
  abort unless c == 13 or c == 10
end

class Version
  include Comparable
  attr_reader :parts

  def initialize(str)
    @parts = str.split(".").map { |i| i.to_i }
  end

  def <=>(other)
    parts <=> self.class.new(other).parts
  end
end

def macos_version
  @macos_version ||= Version.new(`/usr/bin/sw_vers -productVersion`.chomp[/10\.\d+/])
end

def git
  @git ||= if ENV['GIT'] and File.executable? ENV['GIT']
             ENV['GIT']
           elsif Kernel.system '/usr/bin/which -s git'
             'git'
           else
             exe = `xcrun -find git 2>/dev/null`.chomp
             exe if $? && $?.success? && !exe.empty? && File.executable?(exe)
           end

  return unless @git
  # Github only supports HTTPS fetches on 1.7.10 or later:
  # https://help.github.com/articles/https-cloning-errors
  `#{@git} --version` =~ /git version (\d\.\d+\.\d+)/
  return if $1.nil? or Version.new($1) < "1.7.10"

  @git
end

def chmod?(d)
  File.directory?(d) && !(File.readable?(d) && File.writable?(d) && File.executable?(d))
end

def chown?(d)
  !File.owned?(d)
end

def chgrp?(d)
  !File.grpowned?(d)
end

# Invalidate sudo timestamp before exiting
at_exit { Kernel.system "/usr/bin/sudo", "-k" }

####################################################################### script
abort "Don't run this as root!" if Process.uid == 0
if Dir["#{HOMEBREW_PREFIX}/.git/*"].empty?
  abort <<-EOABORT if `/usr/bin/xcrun clang 2>&1` =~ /license/ && !$?.success?
  You have not agreed to the Xcode license.
  Before running the installer again please agree to the license by opening
  Xcode.app or running:
      sudo xcodebuild -license
  EOABORT

  chmods = %w( . bin etc include lib lib/pkgconfig Library sbin share var var/log share/locale share/man
               share/man/man1 share/man/man2 share/man/man3 share/man/man4
               share/man/man5 share/man/man6 share/man/man7 share/man/man8
               share/info share/doc share/aclocal ).
      map { |d| File.join(HOMEBREW_PREFIX, d) }.select { |d| chmod?(d) }
  chowns = chmods.select { |d| chown?(d) }
  chgrps = chmods.select { |d| chgrp?(d) }

  unless chmods.empty?
    ohai "The following directories will be made group writable:"
    puts(*chmods)
  end
  unless chowns.empty?
    ohai "The following directories will have their owner set to #{Tty.underline 39}#{ENV['USER']}#{Tty.reset}:"
    puts(*chowns)
  end
  unless chgrps.empty?
    ohai "The following directories will have their group set to #{Tty.underline 39}admin#{Tty.reset}:"
    puts(*chgrps)
  end

  if File.directory? HOMEBREW_PREFIX
    system "/bin/chmod", "g+rwx", *chmods unless chmods.empty?
    system "/usr/sbin/chown", ENV['USER'], *chowns unless chowns.empty?
    system "/usr/bin/chgrp", "admin", *chgrps unless chgrps.empty?
  else
    system "/bin/mkdir", HOMEBREW_PREFIX
    system "/bin/chmod", "g+rwx", HOMEBREW_PREFIX
    # the group is set to wheel by default for some reason
    system "/usr/sbin/chown", "#{ENV['USER']}:admin", HOMEBREW_PREFIX
  end

  sudo "/bin/mkdir", HOMEBREW_CACHE unless File.directory? HOMEBREW_CACHE
  sudo "/bin/chmod", "g+rwx", HOMEBREW_CACHE if chmod? HOMEBREW_CACHE
  sudo "/usr/sbin/chown", ENV['USER'], HOMEBREW_CACHE if chown? HOMEBREW_CACHE
  sudo "/usr/bin/chgrp", "admin", HOMEBREW_CACHE if chgrp? HOMEBREW_CACHE

  if macos_version >= "10.9"
    developer_dir = `/usr/bin/xcode-select -print-path 2>/dev/null`.chomp
    if developer_dir.empty? || !File.exist?("#{developer_dir}/usr/bin/git")
      ohai "Installing the Command Line Tools (expect a GUI popup):"
      sudo "/usr/bin/xcode-select", "--install"
      puts "Press any key when the installation has completed."
      getc
    end
  end

  ohai "Downloading and installing Homebrew..."
  Dir.chdir HOMEBREW_PREFIX do
    if git
      # we do it in four steps to avoid merge errors when reinstalling
      system git, "init", "-q"

      # "git remote add" will fail if the remote is defined in the global config
      system git, "config", "remote.origin.url", HOMEBREW_REPO
      system git, "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"

      args = git, "fetch", "origin", "master:refs/remotes/origin/master", "-n"
      args << "--depth=1" unless ARGV.include?("--full") || !ENV["HOMEBREW_DEVELOPER"].nil?
      system(*args)

      system git, "reset", "--hard", "origin/master"
    else
      # -m to stop tar erroring out if it can't modify the mtime for root owned directories
      # pipefail to cause the exit status from curl to propagate if it fails
      curl_flags = "fsSL"
      system "/bin/bash -o pipefail -c '/usr/bin/curl -#{curl_flags} #{HOMEBREW_REPO}/tarball/master | /usr/bin/tar xz -m --strip 1'"
    end
  end

  ohai "Installation successful!"

  if macos_version < "10.9" and macos_version > "10.6"
    `/usr/bin/cc --version 2> /dev/null` =~ %r[clang-(\d{2,})]
    version = $1.to_i
    puts "Install the #{Tty.white}Command Line Tools for Xcode#{Tty.reset}: https://developer.apple.com/downloads" if version < 425
  else
    puts "Install #{Tty.white}Xcode#{Tty.reset}: https://developer.apple.com/xcode" unless File.exist? "/usr/bin/cc"
  end
end

require "rubygems"
require "json"

configuration = JSON.parse(open("localbrew.json").read)

configuration["require"].each do |package, options|
  options = options.collect { |option| "--" + option}
  system "#{HOMEBREW_PREFIX}/bin/brew", "reinstall", package, *options
end

