
package App::Term::Jump ;

use strict ;
use warnings ;

use File::Basename ;
use File::Spec ;
use Getopt::Long;
use File::Find::Rule ;
use File::HomeDir ;
use Cwd ;

our $VERSION = '0.03' ;

=head1 NAME 

  jump  

=head1 DESCRIPTION

A utility to navigate your filesystem. It can ither be used directly on the 
command line or integrated with Bash.

=head1 SYNOPSIS

  $> j --add path [weight]

  $> j --remove path

  $> j --search path_part [path_part] ...

  $> j --show_database

=head1 OPTIONS

  --search		search for the best match in the database

  -a|add		add path to database, weight is adjusted if the path exists
			curent path if none is given

  -r|remove		remove path from database,  current path if none is given
  -remove_all		remove all paths from database

  -s|show_database	show database entries
  -show_config_files	show configuration files

  --complete		return completion path, used by bash complete

  -v|version		show version information and exit
  -h|help		show this help

  -no_direct_path	ignore directories directly under cwd
  -no_cwd		ignore directories and sub directories under cwd
  -no_sub_db		ignore directories under the database entries

=head1 FILES

  ~/.jump_database      default database
  ~/.jump_config	optional configuration file, a Perl hash format

=head1 CONFIGURATION FILE FORMAT

	{
	black_listed_directories => [string, qr] , # paths matching are not added to db

	ignore_case => 0, 	# case insensitive search and completion

	no_direct_path => 0, 	# ignore directories directly under cwd
	no_cwd => 0, 		# ignore directories and sub directories under cwd
	no_sub_db => 0, 	# ignore directories under the database entries
	} ;

=head1 ENVIRONMENT

  APP_TERM_JUMP_DB	name of the database file
  APP_TERM_JUMP_CONFIG	name of the configuration file

=head1 NAVIGATION

To naviate your directory structure I<jump> must be integrate with your shell.

TBD

=head1 COMMANDS

=head2 Adding directories

  $> j --add path [weight]

path is added to the directory with optional weight. If no weight is given,
a default weight is assigned. If the entry already exist, the weight is
added to the existing entry. 

Only directories can be added to the database.

Paths matching entries in config I<black_listed_directories> are silently 
ignored

=head2 Removing entries

  $> j --remove_all

The database is emptied

  $> j --remove  path

The the pat is removed from the database

=head2 Increasing and reseting weight

=head3 Increasing weight

  $> j --add path weight

=head3 Resetting weight

  $> j --remove --add path weight

=head2 Show the database contents

  $> j --show_database

=head2 Displa the database file name and the configuration file name

  $> j --show_configuration_files

=head1 MATCHING

  $> j --search  path_part [path_part] ...

path_part is matched in a case sensitie fashion; set $config->{ignore_case} in
the configuration file for matching in a case insensitive fashion.

Given this directory structure, the database entries and cwd being I</>


  /
   A

   path_part
     path_part2
       A (w:10)
       B_directory (w:10)
       C (w:10)
         F

   path_part3
     B (w:1)
     B_directory (w:20)
     C (w:10)
       E
       F

   subdir
     E

Paths are matched in this order:

=over 2

=item * existing full path

Setting configuration I<no_direct_path> disables this matching

=item * match directory under the current working directory

this allow Jump to mimic I<cd>'s behavior. 

  $> jump --search A

will return /A even though /path_part/path_part2/A is a database entry with weight:10 
 
Setting configuration I<no_direct_path> disables this matching

=item * full match last directory of database entry

  $> jump --search B 

will return /path_part/path_part3/B, which has weigh:1 even though /path_part/path_part3/B_directory is a database entry with weight:10 
 
=item *  partial match last directory of database entry

  $> jump --search B_dir

will return /path_part/path_part3/B_directory which is heavier than /path_part/path_part2/B_directory  
 
=item * equivalent matches return the first entry in alphabetical order
 
  $> jump --search C

will return /path_part/path_part2/C which sorts before /path_part/path_part3/C  
 
=item * match part of a db entry

  $> jump --search path 

will return  /path_part/path_part3/C which is the entry containing I<path> and has the heaviest weight 
 
=item * match sub directory of cwd

  $> jump --search E

will return /subdir/E  

Seting configuration I<no_cwd> disables this matching
 
=item * match sub directory of a db entry

  $> jump --search F

will return  /path_part/path_part3/C/F. /path_part/path_part2/F is not under a database entry 

Setting configuration I<no_sub_db> disables this matching

=back

=head2 Matching with multiple path parts

  $> jump --search C

Matches 2 entries but will return /path_part/path_part2/C which sorts before /path_part/path_part3/C, you can
give multiple matches on the command line
   
  $> jump --search 3 C
 
will return /path_part/path_part3/C

=head1 Bash INTEGRATION and --complete

  $> j --complete path_part [path_part] ...

will return a list of matches that an be used to integrate with the I<cd> command. Read add_jump.sh in the distribution

=head1 SEE ALSO

  autojump

=head1 AUTHOR

	Nadim ibn hamouda el Khemir
	CPAN ID: NKH

	Report bugs on Github or CPAN
=cut

#------------------------------------------------------------------------------------------------------------------------

my $FIND_ALL = 1 ;
my $FIND_FIRST = 0 ;

our $debug ;
our ($no_direct_path, $no_cwd, $no_sub_db) ;

sub run
{
my (@command_line_arguments) = @_ ;

my ($search, $add, $remove, $remove_all, $show_database, $show_configuration_files, $version, $complete) ;

{
local @ARGV = @command_line_arguments ;

die 'Error parsing options!'unless 
        GetOptions
                (
		'search' => \$search,
		'complete' => \$complete,

		'a|add' => \$add,
		'r|remove' => \$remove,
		'remove_all' => \$remove_all,

		's|show_database' => \$show_database,

		'show_configuration_files' => \$show_configuration_files,
		'v|V|version' => \$version,
                'h|help' => \&show_help, 

		'no_direct_path' => \$no_direct_path,
		'no_cwd' => \$no_cwd,
		'no_dub_db' => \$no_sub_db,

		'd|debug' => \$debug,
                ) ;

@command_line_arguments = @ARGV ;
}

# warning, if multipe commands are given on the command line, jump will run them at the same time
	
warn "\nJump: Error: no command given" unless 
	grep {defined $_} ($search, $add, $remove, $remove_all, $show_database, $show_configuration_files, $version, $complete) ;

my @results;

remove_all(@command_line_arguments) if($remove_all) ;
remove(@command_line_arguments) if($remove) ;

add(@command_line_arguments) if($add) ;

@results = complete(@command_line_arguments) if($complete) ;
@results = search(@command_line_arguments) if($search) ;

show_database() if($show_database) ;
show_configuration_files() if($show_configuration_files) ;
show_version() if($version) ;

return @results ;
}

#------------------------------------------------------------------------------------------------------------------------

sub complete
{
my (@arguments) = @_ ;

my (@matches) = find_closest_match($FIND_ALL, @_) ;

print $_->{path} . "\n" for @matches ;

return (@matches) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub search
{
my (@matches) = find_closest_match($FIND_FIRST, @_) ;

if(@matches) 
	{
	print $matches[0]{path} . "\n" ;
	}

return (@matches) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub find_closest_match
{
my ($find_all, @paths) = @_ ;

return unless @paths ;
	
my $cwd = cwd() ;

warn "\nApp::Term::Jump::find_closest_match:\n" if $debug ;

my $path_to_match = join('.*', @paths) ;
my $end_directory_to_match = $paths[-1] ;
my $path_to_match_without_end_directory =  @paths > 1 ? join('.*', @paths[0 .. $#paths-1]) : qr// ;
$path_to_match_without_end_directory =~ s[^\./][$cwd] ;

use Data::TreeDumper ;
warn DumpTree
	{
	paths => \@paths,
	path => $path_to_match_without_end_directory,
	end_directory => $end_directory_to_match,
	} if $debug ;

my %matches ;

# find possible approximations and jumps, including minor path jumps

my (@direct_matches, @directory_full_matches, @directory_partial_matches, @path_partial_matches, @cwd_sub_directory_matches, @sub_directory_matches) ;

my ($config) = get_config() ;
my $db = read_db() ;
	
warn "matching direct path\n" if $debug ;
if(1 == @paths && !$config->{no_direct_path})
	{
	my $path_to_match = $paths[0] ;

	if($path_to_match =~ m[^/] && -d $path_to_match)
		{
		warn "matches full path in file system\n" if $debug ;

		push @direct_matches, {path => $path_to_match, weight => 0,cumulated_path_weight => 0,  matches => 'full path in file system'} 
			unless exists $matches{$path_to_match} ;

		$matches{$path_to_match}++ ;
		}
	elsif(-d $cwd . '/' . $path_to_match)
		{
		warn "matches directory under cwd\n" if $debug ;

		$path_to_match =~ s[^\./+][] ;
		$path_to_match =~ s[^/+][] ;
		
		push @direct_matches, {path => $path_to_match, weight => 0, cumulated_path_weight => 0, matches => 'directory under cwd'} 
			unless exists $matches{$path_to_match} ;
		
		$matches{$path_to_match}++ ;
		}
	}

my $ignore_case = $config->{ignore_case} ? '(?i)' : '' ;

warn "matching directories in database\n" if $debug ;
for my $db_entry (sort keys %{$db})
	{
	my @directories = File::Spec->splitdir($db_entry) ;
	my $db_entry_end_directory = $directories[-1] ;

	my $weight = $db->{$db_entry} ;
	my $cumulated_path_weight = get_paths_weight($db, @directories) ;	

	# match end directory
	if($db_entry_end_directory =~ /$ignore_case^$end_directory_to_match$/)
		{
		if($db_entry =~  /$ignore_case$path_to_match/)
			{
			warn "matches end directory in db entry\n" if $debug ;

			push @directory_full_matches, 
				{ path => $db_entry, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'end directory in db entry' } 
					unless exists $matches{$db_entry} ;
			
			$matches{$db_entry}++ ;
			}
		}
	elsif($db_entry_end_directory =~ /$ignore_case$end_directory_to_match/)
		{
		if($db_entry =~  /$ignore_case$path_to_match/)
			{
			warn "matches part of end directory in db entry\n" if $debug ;

			push @directory_partial_matches,
				{ path => $db_entry, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'part of end directory in db entry'} 
					unless exists $matches{$db_entry} ;

			$matches{$db_entry}++ ;
			}
		}
	elsif(my ($part_of_path_matched) = $db_entry =~  m[$ignore_case(.*$path_to_match.*?)/])
		{
		warn "matches part of path in db entry\n" if $debug ;
		
		push @path_partial_matches, 
			{ path => $part_of_path_matched, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'part of path in db entry'} 
					unless exists $matches{$part_of_path_matched} ;
			
		$matches{$part_of_path_matched}++ ;
		}

# sort by path, path weight, alphabetically
@directory_full_matches = 
	sort {$b->{weight} <=> $a->{weight} || $b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{path} cmp $b->{path}} 
		@directory_full_matches ;

@directory_partial_matches = 
	sort {$b->{weight} <=> $a->{weight} || $b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{path} cmp $b->{path}} 
		@directory_partial_matches ;

@path_partial_matches = 
	sort {$b->{weight} <=> $a->{weight} || $b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{path} cmp $b->{path}} 
		@path_partial_matches ;
	}
	
if(! $config->{no_cwd} && ($find_all || 0 == keys %matches))
	{
	warn "matching sub directories under cwd\n" if $debug ; 

	for my $directory (sort File::Find::Rule->directory()->in($cwd))
		{
		my $sub_directory = $directory =~ s[^$cwd][]r ;
		my $cwd_path_to_match = $path_to_match =~ s[^\./][/]r ;

		if(my ($part_of_path_matched) = $sub_directory =~  m[$ignore_case(.*$cwd_path_to_match.*?)(/|$)])
			{
			warn "matches sub directory under cwd\n" if $debug ;

			my @directories = File::Spec->splitdir($part_of_path_matched) ;
			my $cumulated_path_weight = get_paths_weight($db, @directories) ;

			push @cwd_sub_directory_matches, {path => "$cwd$part_of_path_matched", weight => 0, cumulated_path_weight => $cumulated_path_weight, matches => 'sub directory under cwd'}
				unless exists $matches{"$cwd$part_of_path_matched"} ;

			$matches{"$cwd$part_of_path_matched"}++ ;
			} 
		}
	
	@cwd_sub_directory_matches = sort {$b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{path} cmp $b->{path}} @cwd_sub_directory_matches ;
	}

if(! $config->{no_sub_db} && ($find_all || 0 == keys %matches))
	{
	warn "matching directories under database entries\n" if $debug ; 
 
	for my $db_entry (sort {length($b) <=> length($a) || $b cmp $a} keys %{$db})
		{
		my $cumulated_path_weight = get_paths_weight($db, File::Spec->splitdir($db_entry)) ;	

		for my $directory (sort File::Find::Rule->directory()->in($db_entry))
			{
			if(my ($part_of_path_matched) = $directory =~  m[$ignore_case(.*$path_to_match.*?)(/|$)])
				{
				warn "matches sub directory under database entry\n" if $debug ;
				push @sub_directory_matches, 
					{path => $part_of_path_matched, weight => 1, cumulated_path_weight => $cumulated_path_weight, matches => 'sub directory under a db entry'} 
						unless exists $matches{$part_of_path_matched} ;

				$matches{$part_of_path_matched}++ ;
				} 
			}
		}  

	@sub_directory_matches = 
		sort {$b->{weight} <=> $a->{weight} || $b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{path} cmp $b->{path}} 
			@sub_directory_matches ;
	}

return (@direct_matches, @directory_full_matches, @directory_partial_matches, @cwd_sub_directory_matches, @sub_directory_matches, @path_partial_matches) ;
}
				
sub get_paths_weight
{
my ($db, @directories) = @_ ;

# TODO: handle CWD

my $cumulated_path_weight = 0 ;

my $path ;
for my $directory (@directories)
	{
	next if $directory eq '' ;

	$path .= '/' . $directory ;
	$cumulated_path_weight += $db->{$path} if exists $db->{$path} ;
	}

return $cumulated_path_weight ;
}


#------------------------------------------------------------------------------------------------------------------------

sub remove
{
my ($weight, $path) = check_weight_and_path(@_) ;

my $db = read_db() ;

delete $db->{$path} ;

write_db($db) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub add
{
my ($weight, $path) = check_weight_and_path(@_) ;

if(! is_blacklisted($path))
	{
	my $db = read_db() ;

	if(exists $db->{$path})
		{
		$db->{$path} += $weight ;
		} 
	else
		{
		$db->{$path} = $weight ;
		}

	write_db($db) ;
	}

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub remove_all
{
my %new_db ;

if(0 == @_)
	{
	# no argument, remove all entries
	}
else
	{
	my $db = read_db() ;

	for my $key (keys %{$db})
		{
		my $delete_key = 0 ;

		for my $delete_regex (@_)
			{
			if($key =~ $delete_regex)
				{
				$delete_key++ ;
				last ;
				}
			}
	
		$new_db{$key} = $db->{$key} unless $delete_key ;
		}			
	}

write_db(\%new_db) ;

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub show_database
{
my $db = read_db() ;

for my $path (sort {$db->{$b} <=> $db->{$a}} keys %{$db} )
	{
	print "$db->{$path} $path\n" ;
	}

return ;
}


#------------------------------------------------------------------------------------------------------------------------

sub show_configuration_files
{

print get_db_location() . "\n" ;
print get_config_location() . "\n" ;

return ;
}


#------------------------------------------------------------------------------------------------------------------------

sub show_version
{
print "Jump version $VERSION\n" ;

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub get_db_location
{
return  defined $ENV{APP_TERM_JUMP_DB} ? $ENV{APP_TERM_JUMP_DB} : home() . '/.jump_db' ;
}

#------------------------------------------------------------------------------------------------------------------------

sub get_config_location
{
return  defined $ENV{APP_TERM_JUMP_CONFIG} ? $ENV{APP_TERM_JUMP_CONFIG} : home() . '/.jump_config'  ;
}

#------------------------------------------------------------------------------------------------------------------------

sub get_config
{

my $config_location = get_config_location() ;
my $config = {} ;

if(-f $config_location)
	{
	unless ($config = do $config_location) 
		{
		warn "couldn't parse $config_location: $@" if $@;
		warn "couldn't do $config_location: $!"    unless defined $config;
		warn "couldn't run $config_location"       unless $config;
		}
	}

$config->{no_direct_path} = $no_direct_path if defined $no_direct_path ;
$config->{no_cwd} = $no_cwd if defined $no_cwd ;
$config->{no_sub_db} = $no_sub_db if defined $no_sub_db ;

return
	{
	ignore_case => 0, 	#case insensitive search and completion
	no_direct_path => 0, 	#ignore directories directly under cwd
	no_cwd => 0, 		#ignore directories and sub directories under cwd
	no_sub_db => 0, 	#ignore directories under the database entries

	black_listed_directories => [] ,

	%{$config},
	} ;
}

#------------------------------------------------------------------------------------------------------------------------

sub read_db
{
my ($db) = @_ ;
my %db ;

my $regex = qr/(\d+)\ (.*)/ ;

use IO::File ;

my $db_fh = IO::File->new() ;

if($db_fh->open(get_db_location(), 'r'))
	{
	while(my $line = <$db_fh>)
		{
		my ($w, $p) = ($line =~ m/$regex/) ; 

		if(defined $w && defined $p)
			{
			$db{$p} = $w ;
			}
		else	
			{
			}
		}
	}

return \%db ;
}

#------------------------------------------------------------------------------------------------------------------------

sub write_db
{
my ($db) = @_ ;

open my $db_fh, '>', get_db_location() ;

while(my ($p, $w) = each %{$db})
	{
	if(-d $p)
		{
		if($w < 0)
			{
			print "Jump: Error weight value is negative, setting to zero.\n" ;
			$w = 0 ;
			}

		$p =~ s[  /$   ] []x ; # remove trailing /
			
		print $db_fh "$w $p\n" ;
		}	
	else
		{
		warn "Jump: Warning, directory '$p' doesn not exist, ignoring it.\n" ;
		}
	}

return ;
}


#------------------------------------------------------------------------------------------------------------------------

sub check_weight_and_path
{
my ($weight, $path) = @_ ;

if(defined $weight)
	{
	if(defined $path)
		{
		if( -d $weight && ! -d $path)
			{
			($weight, $path) = ($path, $weight) ;
			}
		}
	else
		{
		if(-d $weight || $weight !~ /^\d+$/)
			{
			$path = $weight ;
			undef $weight ;
			}
		}
	}

$weight = 1 unless defined $weight ;

if(defined $path)
	{
	if('.' eq $path)
		{
		$path = cwd() ;
		}
	else
		{
		$path = cwd() . '/' . $path unless $path =~ m[^/] ;
		}
	}
else
	{
	$path = cwd() ;
	}

return ($weight, $path) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub is_blacklisted
{
my ($path) = @_ ;

my ($config) = get_config() ;

return grep {$path =~ $_} @{ $config->{black_listed_directories} } ; 
}

#------------------------------------------------------------------------------------------------------------------------

sub show_help
{ 
print STDERR `perldoc App::Term::Jump`  or warn 'Can\'t display help!' ; ## no critic (InputOutput::ProhibitBacktickOperators)
exit(1) ;
}

#------------------------------------------------------------------------------------------------------------------------

1;


