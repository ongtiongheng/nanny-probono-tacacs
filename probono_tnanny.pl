#!/usr/local/bin/perl5
#
#  probono_tacacs_nanny – hehe, you know...
#
#  This code was based on Curt Sampson <cjs@cynic.net> poprelayd and modified
#  by Patrick Wayne <ongtiongheng@gmail.com> into a nanny daemon.
#  $Id: probono_tnanny,v 1.1.1.1 2017/07/06 11:14:00 oth Exp $
#
#  Usage:
#       probono_tnanny -d
#
#  With the -d option this program goes into daemon mode. It will
#  monitor <$path>/tac_plus.probono.conf for configuration changes. 
#  When it sees configuration changes, it will restart the probono tacacs
#

#
#  Configuration settings.
#

$configfile = "/opt/tac_plus/tac_plus.probono.conf";   # Probono Tacacs config.
$pidfile = "/var/run/probono_tnanny.pid";              # Where we put our PID.
$log_wait_interval = 5;				       # Number of seconds between checks
					               # of the log file.

#
#  Modules
#

use Getopt::Std;
use Fcntl;
use Fcntl qw(:flock);
use POSIX;

# You may need to uncomment this if your fcntl.ph doesn't export it.
#sub O_EXLOCK { 0x20 };

#
#  Variables
#

undef $pid;                             # Process ID.
undef $lffd;                            # $lines in file, file descriptor.
undef $lfino;                           # Inode of $lines in file 
                                        # when we opened it.
undef $lasttimeout;			# Last time we did a timeout.

#
#  Subroutines
#


# getlogline()
#
# Return the next line from $lines in config file, or undef if one isn't 
# currently ready.
#
# XXX Note that there's a bug in this routine that causes it to ignore
# blank lines. I kinda like this behaviour, so I've not fixed it.
#
sub getlogline {
    my $junk;
    my $ino;
    my $foundeof = 0;
    my $buf;
    my $count;

    # The first time we're called; open the lines in conf file, skip to the end,
    # and remember the inode we opened.
    if (!defined($lffd))  {
        $lffd = POSIX::open($configfile, O_RDONLY|O_NONBLOCK, 0);
        if (!defined($lffd))  {
            die "Can't open $configfile\n";
        }
        if (POSIX::lseek($lffd, 0, &POSIX::SEEK_END) == -1)  {
            die "Can't seek to end of $configfile\n";
        }
        ($junk, $lfino, $junk) = POSIX::fstat($lffd);
    }

    # Append new data, if available, to our buffer.
    $count = POSIX::read($lffd, $buf, 1024);
    if ($count)  {
        $lfbuf = $lfbuf . $buf;
    }

    # Return a line, if we have one.
    if ($lfbuf =~ m/\n/m)  {
        ($buf, $lfbuf) = split(/\n/m, $lfbuf, 2);
        return $buf;
    }

    # Check the inode number of $configfile; if it's not the saved one,
    # the configfile has been rotated and we need to reopen.
    ($junk, $ino, $junk) = POSIX::stat($configfile);
    if ($ino != $lfino)  {
        POSIX::close($lf_fd);
        undef($lf_fd);
        $lffd = POSIX::open($configfile, O_RDONLY|O_NONBLOCK, 0);
        if (!defined($lffd))  {
            die "Can't open $configfile\n";
        }
        ($junk, $lfino, $junk) = POSIX::fstat($lffd);
	return "NEW";
    }
    return undef;
}



#  cleanup
#
#  Clean up and exit; executed on receipt of a sighup.
#
sub cleanup {
    unlink $pidfile;
    exit 0;
}

#
#  Main Program
#

$countopts = 0;
getopts('dk') || \
    die "Usage: probono_tnanny [-d] [-k]\n";

# Daemon mode.
if ($opt_d)  {
    # Check to see we can read/write the files we need.
    die "Can't read $configfile: $!\n" if ! -r $configfile;

    # Become a daemon: fork, detach, cd /, set creation mode to 0.
    if ($pid = fork)  {
        exit 0;                         # Parent.
    } elsif (defined($pid)) {
        $pid = getpid;                  # Child.
    } else {
        die "Can't fork: $!\n";
    }
    # Catch signals.
    $SIG{INT} = \&cleanup;
    $SIG{TERM} = \&cleanup;
    $SIG{HUP} = \&cleanup;
    # Starting script
    open(my $script_fh, '<', $0)
     or die("Unable to open script source: $!\n");
    unless (flock($script_fh, LOCK_EX|LOCK_NB)) {
     print "$0 is already running. Exiting.\n";
     exit(1);
    }
    # Write PID file.
    open(PIDFILE, ">$pidfile") || die "Can't open PID file: $!\n";
    print PIDFILE "$pid\n";
    close(PIDFILE);
    chmod(0644, $pidfile);
    # Detach from terminal, etc.
    setpgrp(0, 0);
    close(STDIN); close(STDOUT); close(STDERR);
    chdir("/");

    # Main loop.
    $lasttimeout = 0;
    while (1)  {
        # Build list of addresses of recent authentications.
         $line = getlogline; 
         if ($line =~ "NEW")  {
		system("/usr/sbin/service tac_plus stop && /usr/sbin/service tac_plus start");
         }
        sleep $log_wait_interval;
    }
}

if ($opt_k) {
  system("kill -9 `cat /var/run/probono_tnanny.pid` > /dev/null 2>/dev/null"); 
}

if (! $countopts)  {
    die "Usage: probono_tnanny [-d] [-k]\n";
}
