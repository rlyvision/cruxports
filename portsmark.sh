#!/usr/bin/perl -w

our $version = "1.1-md";

########################################################################
#
# portspage (Markdown version)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# This is a script for generating CRUX port listings in Markdown format.
# Distributed under the terms of the GPL license.
#
########################################################################

use strict;
use Cwd qw(cwd getcwd);
use File::Basename;

our %options =
(
  title => "CRUX ports",
  timestamp_accuracy => 1,
  date_from_file => 0,
);
our @updates; our @ports;
our %parity = ( 0 => "even", 1 => "odd" );

sub print_usage {
  my $ok = shift;
  print STDERR <<EOT;
Usage: portspage-md [OPTION]... [DIRECTORY [port1...portN]]

  --title=TITLE               set the page title
  --header=FILE               name of file to insert before port listing
  --footer=FILE               name of file to insert after port listing
  --timestamp-accuracy=LEVEL  0 = no timestamp, 1 = date only, 2 = date and time
                              default is 1
  --date-from-file            take date from newest file instead of directory
  --date-from-pkgfile         take date from Pkgfile instead of directory
  --version                   output version information and exit
  [DIRECTORY]                 specify a collection other than \$PWD
  [port1...portN]             individual ports to overwrite (or insert)
                              in an existing index.md

Report bugs to <jmcquah\@disroot dot org>.
EOT
  exit $ok;
}

sub parse_args {
  while (my $arg=shift @ARGV) {
    if ($arg =~ /^--header=(.*)$/) {
      $options{header} = $1;
    }
    elsif ($arg =~ /^--footer=(.*)$/) {
      $options{footer} = $1;
    }
    elsif ($arg =~ /^--title=(.*)$/) {
      $options{title} = $1;
    }
    elsif ($arg =~ /^--timestamp-accuracy=(0|1|2)$/) {
      $options{timestamp_accuracy} = $1;
    }
    elsif ($arg eq "--date-from-file") {
      $options{date_from_file} = 1;
    }
    elsif ($arg eq "--date-from-pkgfile") {
      $options{date_from_pkgfile} = 1;
    }
    elsif ($arg eq "--version") {
      print "$version\n";
      exit 0;
    }
    elsif ($arg eq "--help") {
      print_usage(0);
    }
    elsif (! $options{directory}) {
      (-d $arg) or print_usage(1);
      $options{directory} = $arg;
    }
    else {
      push @updates, $arg;
    }
  }
  $options{directory} = "." if (! $options{directory});
}

sub main {
  parse_args();

  if (@updates) { # individual ports passed as args.
                  # Discard any that are invalid.
      foreach my $port (@updates) {
        if (-f "$options{directory}/$port/Pkgfile") {
          push @ports, $port;
        } else {
          print STDERR "$port not found in $options{directory}, ignoring.\n";
        }
      }
  } else {
      foreach my $file (glob($options{directory} . "/*/Pkgfile")) {
        my $port = (split /\//, $file)[-2];
        push @ports, $port;
      }
  }

  # Print Markdown header
  print "# $options{title}\n\n";

  if ($options{header}) {
    open(my $hH, $options{header}) or die "Couldn't open header file";
    while (<$hH>) {
      print $_;
    }
    close($hH);
    print "\n";
  }

  my $count = 0;
  my $firstrun = 0;
  if (@updates) { # when an existing index.md only needs a quick update
    my @queue = sort @ports;
    my %followH; my $oH; my $col_checked=0; my $oline; my $oname; my $fname;
    my @oldIdx = glob($options{directory} . "/index.md");
    if ($#oldIdx >= 0) {
        # check how many columns the existing index has, and modify our options accordingly
        open ($oH, $oldIdx[0]);
        while (($options{timestamp_accuracy}>0) and ($col_checked==0) and ($oline = <$oH>)) {
            if ($oline =~ m/^\| Port \|/) {
                $options{timestamp_accuracy} -= ($oline =~ m/Last modified/) ? 0 : $options{timestamp_accuracy};
                $col_checked = 1;
            }
        }
    } else {
        $firstrun = 1;
    }
    tablehead();

    HROW: while (my $p = shift @queue) {
        if ($firstrun == 1) {
            $count++;
            mdrow($count,$p);
            next HROW;
        }
        # Shift entries from the old markdown index until we find a successor to the current arg
        while ( (! $followH{$p}) and ($oline=<$oH>) ) {
            chomp($oline);
            next if ($oline !~ m/^\|/);
            next if ($oline =~ m/^\|[-:\s|]+\|/); # Skip separator row
            $oname = $oline;
            $oname =~ s/^\| \[([^\]]+)\].*$/$1/;
            if ($oname lt $p) { 
                $count++;
                print "$oline\n";
            } elsif ($oname eq $p) {
                $count++;
                mdrow($count, $p);
            } else {
                $count++;
                mdrow($count, $p);
                $followH{$p} = "$oline\n";
            }
            # Before breaking out of the loop, append all the packages from the queue that 
            # are lexographically earlier than the current entry in the old markdown index.
            while (($queue[0]) and ($queue[0] le $oname)) {
                $p = shift @queue;
                $count++;
                mdrow($count, $p);
                $followH{$p} = "$oline\n" if ($p lt $oname);
            }
        }
        # Either the old index has a successor to the current arg, or all remaining args
        # should be appended at the end of the markdown table.
        if (! $followH{$p}) {
            $count++;
            mdrow($count, $p);
            while ($p = shift @queue) {
                $count++; mdrow($count, $p);
            }
        }
        # Args still remaining in the queue means that the old index hasn't been exhausted.
        if (@queue) {
            $fname = $followH{$p};
            $fname =~ s/^\| \[([^\]]+)\].*$/$1/; 
            if ($queue[0] gt $fname) {
                $count++;
                print $followH{$p};
            } else {
                $followH{$queue[0]} = $followH{$p};
            }
        }
        # Shift another port from the queue
    }
    # Now append the tail of the old markdown index.
    while (($firstrun == 0) and ($oline = <$oH>)) {
        if ($oline =~ m/^\|/ && $oline !~ m/^\|[-:\s|]+\|/) {
            $count++;
            print $oline;
        }
    }
    ($firstrun == 1) or close($oH);
  }
  else { # No individual ports specified, just process the entire collection
    tablehead();
    foreach my $port (@ports) {
        $count++;
        mdrow($count, $port);
    }
  }

  # Close the markdown table and append the footer
  print "\n";
  print "**$count ports**\n\n";

  if ($options{footer}) {
      open(my $fH, $options{footer}) or die "Couldn't open footer file";
      while (<$fH>) {
          print $_;
      }
      close($fH);
      print "\n";
  }

  print "*Generated by portspage-md $version on " . isotime() . "*\n";

  return 0;
}

sub tablehead {
    my $CWD = getcwd;
    my $repo = (split /\//, $CWD)[-1];
    my $pubkey = "/etc/ports/".$repo.".pub";
    if ( (-e $pubkey) and open(my $kH, $pubkey) ) {
      while (my $line = <$kH>) {
        chomp $line;
        if ($line !~ "untrusted comment") {
          print "**Signify public key:** `$line`\n\n";
        }
      }
      close($kH);
    }
    
    # Create markdown table header
    print "| Port | Version | Description |";
    if ($options{timestamp_accuracy} > 0) {
      print " Last modified |";
    }
    print "\n";
    
    print "|------|---------|-------------|";
    if ($options{timestamp_accuracy} > 0) {
      print "---------------|";
    }
    print "\n";
}

sub mdrow {
    my ($count, $p) = @_;
    my ($url, $version, $release, $pver, $desc, $date);

    open (my $pF, "$options{directory}/$p/Pkgfile") or die "$p/Pkgfile unreadable!";
    while (<$pF>) {
      if ($_ =~ /^#\s*URL:\s*(.*)$/) {
        $url = $1;
        $url =~ s/</&lt;/g;
        $url =~ s/>/&gt;/g;
        $url =~ s/&/&amp;/g;
      } elsif ($_ =~ /^#\s*Description:\s*(.*)$/) {
        $desc = $1;
      } elsif ($_ =~ /^version=(.*)$/) {
        $version = $1;
      } elsif ($_ =~ /^release=(.*)$/) {
        $release = $1;
      }
    }
    close ($pF);
    $pver = $version ."-". $release;
    if ($options{timestamp_accuracy} > 0) {
      if ($options{date_from_file}) {
        my @dates;
        foreach my $file (glob($options{directory}."/".$p."/*")) {
          push (@dates, (stat($file))[9]);
        }
        $date = (sort @dates)[-1];
      }
      elsif ($options{date_from_pkgfile}) {
        $date = (stat("$options{directory}/$p/Pkgfile"))[9];
      }
      else {
        $date = (stat("$options{directory}/$p"))[9];
      }
    }
   
    print "| ";
    if ($url) {
      print "[$p]($url)";
    } else {
      print $p;
    }
    print " | ";
    print "[$pver]($options{directory}/$p/)";
    print " | ";
    print ($desc // "");
    print " | ";
    if ($date) {
      print isotime($date, $options{timestamp_accuracy});
    } else {
      print "";
    }
    print " |\n";
}

sub isotime {
  my $time = (shift or time);
  my $accuracy = (shift or 2);
  my @t = gmtime ($time);
  my $year = $t[5] + 1900;
  my $month = sprintf("%02d", $t[4] + 1);
  my $day = sprintf("%02d", $t[3]);

  if ($accuracy == 1) {
    return "$year-$month-$day";
  }

  return "$year-$month-$day " . sprintf("%02d:%02d:%02d UTC", $t[2], $t[1], $t[0]);
}

exit(main());

# End of file
