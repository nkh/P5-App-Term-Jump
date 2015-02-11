
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
  -show_setup_files	show database entries

  --complete		return completion path, used by bash complete

  -v|version		show version information and exit
  -h|help		show this help

=head1 FILES

  ~/.jump_database      default database
  ~/.jump_config	optional configuration file, a Perl hash format

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

=head1 ADDING DIRECTORIES

  $> j --add path [weight]

path id added to the directory with optional weight. If no weight is given,
a default weight is assigned. If the entry already exist, the weight is
added to the existing entry. 

Only directories can be added to the database.

Paths matching entries in $config->[black_listed_directories] are silently 
ignored

=head1 OTHER FUNCTIONALITY

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

  $> j --show_setup_files

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

=item * match directory under the current working directory

this allow Jump to mimic I<cd>'s behavior. 

  $> jump --search A

will return /A even though /path_part/path_part2/A is a database entry with weight:10 
 
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
 
=item * match sub directory of a db entry

  $> jump --search F

will return  /path_part/path_part3/C/F. /path_part/path_part2/F is not under a database entry 
 
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

sub run
{
my (@command_line_arguments) = @_ ;

my ($search, $add, $remove, $remove_all, $show_database, $show_setup_files, $version, $complete) ;

{
local @ARGV = @command_line_arguments ;

die 'Error parsing options!'unless 
        GetOptions
                (
		'search' => \$search,

		'a|add' => \$add,
		'r|remove' => \$remove,
		'remove_all' => \$remove_all,

		's|show_database' => \$show_database,
		'show_setup_files' => \$show_setup_files,
		'v|V|version' => \$version,

		'complete' => \$complete,

                'h|help' => \&show_help, 
                
                'dump_options' => 
                        sub 
                                {
                                print join "\n", map {"-$_"} 
                                        qw(
                                        search
					add
					remove
					remove_all
					show_database
					version
					complete
					help
                                        ) ;
                                        
                                exit(0) ;
                                },

                ) ;

@command_line_arguments = @ARGV ;
}

# warning, what if multipe commands are given on the command line, jump will run them at the same time
	
warn 'Jump: Error: no command given' unless grep {defined $_} ($search, $add, $remove, $remove_all, $show_database, $show_setup_files, $version, $complete) ;

my @results;

remove_all() if($remove_all) ;
remove(@command_line_arguments) if($remove) ;

add(@command_line_arguments) if($add) ;

@results = complete(@command_line_arguments) if($complete) ;
@results = search(@command_line_arguments) if($search) ;

show_database() if($show_database) ;
show_setup_files() if($show_setup_files) ;
show_version() if($version) ;

return @results ;
}

#------------------------------------------------------------------------------------------------------------------------

sub complete
{
my ($index, $command, @arguments) = @_ ;
$index-- ;

my (@matches) = find_closest_match($index, @_) ;

=pod comment 
if(@matches)
	{
	print join("\n", @matches) . "\n" ;
	}
=cut

use Data::TreeDumper;
print DumpTree $_ for (@matches) ;

return (@matches) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub search
{
my (@matches) = find_closest_match(undef, @_) ;

if(@matches) 
	{
	print $matches[0]{path} . "\n" ;
	
	#TODO: increment weight in database and add if direct directory
	}

return (@matches) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub find_closest_match
{
my ($index, @paths) = @_ ;
	
my $cwd = cwd() ;

my $path_to_match = join('.*', @paths) ;
my $end_directory_to_match = $paths[-1] ;
my $path_to_match_without_end_directory =  @paths > 1 ? join('.*', @paths[0 .. $#paths-1]) : qr// ;
$path_to_match_without_end_directory =~ s[^\./][$cwd] ;

my $matched = 0 ;

# find possible approximations and jumps, including minor path jumps

my (@direct_matches, @directory_full_matches, @directory_partial_matches, @path_partial_matches, @cwd_sub_directory_matches, @sub_directory_matches) ;

my ($config) = get_config() ;
my $db = read_db() ;

if(1 == @paths && !$config->{no_direct_path})
	{
	my $path_to_match = $paths[0] ;

	if($path_to_match =~ m[^/] && -d $path_to_match)
		{
		# matches full path in file system
		$matched++ ;
		push @direct_matches, {path => $path_to_match, weight => 0, matches => 'full path in file system'} ;
		}
	elsif(-d $cwd . '/' . $path_to_match)
		{
		# matches full path in file system
		$matched++ ;
		
		$path_to_match =~ s[^\./+][] ;
		$path_to_match =~ s[^/+][] ;
		push @direct_matches, {path => $path_to_match, weight => 0, matches => 'direct path under cwd'} ;
		}
	}

my $ignore_case = $config->{ignore_case} ? '(?i)' : '' ;

if(0 == $matched)
	{
	for my $db_entry (keys %{$db})
		{
		my @directories = File::Spec->splitdir($db_entry) ;
		my $db_entry_without_end_directory = join('/', @directories[0 .. $#directories-1]) ;

		my $weight = $db->{$db_entry} ;
		my $cumulated_path_weight = get_paths_weight($db, @directories) ;	

		# match end directory
		if($directories[-1] =~ /$ignore_case^$end_directory_to_match$/)
			{
			# matches the end directory completely

			if($db_entry_without_end_directory =~ $path_to_match_without_end_directory)
				{
				$matched++ ;
				push @directory_full_matches, 
					{ path => $db_entry, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'end directory' } ;
				}
			}
		elsif($directories[-1] =~ /$ignore_case$end_directory_to_match/)
			{
			# matches part of the end diretory

			if($db_entry_without_end_directory =~ $path_to_match_without_end_directory)
				{
				$matched++ ;
				push @directory_partial_matches,
					{ path => $db_entry, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'part of end directory'} ;
				}
			}
		elsif($db_entry =~ /$ignore_case$path_to_match/)
			{
			# matches part of the path
			$matched++ ;
			push @path_partial_matches, 
				{ path => $db_entry, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'part of path'} ;
			}
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
	
if(0 == $matched && ! $config->{no_cwd})
	{
	# match directories under currend working directory 

	for my $directory (File::Find::Rule->directory()->in($cwd))
		{
		my $sub_directory = $directory =~ s[^$cwd][]r ;
		my $cwd_path_to_match = $path_to_match =~ s[^\./][/]r ;

		if($sub_directory =~ $cwd_path_to_match)
			{
			push @cwd_sub_directory_matches, {path => $directory, weight => 0, matches => 'directory under cwd'} ;
			} 
		}
	
	@cwd_sub_directory_matches = sort {$a->{path} cmp $b->{path}} @cwd_sub_directory_matches ;
	$matched++ if @cwd_sub_directory_matches ;
	}

if(0 == $matched && ! $config->{no_sub_db})
	{
	# match directories under entries in db
 
	for my $db_entry (keys %{$db})
		{
		my @directories = File::Spec->splitdir($db_entry) ;
		my $db_entry_without_end_directory = join('/', @directories[0 .. $#directories-1]) ;
		
		my $weight = $db->{$db_entry} ;
		my $cumulated_path_weight = get_paths_weight($db, @directories) ;	

		for my $directory (File::Find::Rule->directory()->in($db_entry))
			{
			my $sub_directory = $directory =~ s[^$db_entry_without_end_directory][]r ;
			
			if($sub_directory =~ $path_to_match)
				{
				push @sub_directory_matches, {path => $directory, weight => 1, cumulated_path_weight => $cumulated_path_weight, matches => 'directory under a db entry'} ;
				} 
			}
		}  
	
	@sub_directory_matches = 
		sort {$b->{weight} <=> $a->{weight} || $b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{path} cmp $b->{path}} 
		@sub_directory_matches ;
	
	$matched++ ;
	}

# grep all paths in the filesystem

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
my %empty_db ;

write_db(\%empty_db) ;

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

sub show_setup_files
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
		warn "Jump: Error '$p' is not a directory.\n" ;
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
	$path = cwd() . '/' . $path unless $path =~ m[^/] ;
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



