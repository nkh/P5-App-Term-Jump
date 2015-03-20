
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

=head1 CONFIGURATION

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

# grep all paths in the filesystem
# if option is set
# if option to ask is set
# if answer is positive
# do we stop at first match?

 
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

my ($search, $add, $remove, $remove_all, $show_database, $show_setup_files, $version, $complete, $generate_bash_completion) ;

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

		'show_setup_files' => \$show_setup_files,
		'v|V|version' => \$version,
                'h|help' => \&show_help, 
		'generate_bash_completion' => \$generate_bash_completion,
                ) ;

@command_line_arguments = @ARGV ;
}

# warning, what if multipe commands are given on the command line, jump will run them at the same time
	
warn 'Jump: Error: no command given' unless grep {defined $_} ($search, $add, $remove, $remove_all, $show_database, $show_setup_files, $version, $complete) ;

generate_bash_completion
	(
	qw(
		search
		complete

		add
		remove
		remove_all

		show_database

		show_setup_files
		version
                help
		generate_bash_completion
		
		)
	) if $generate_bash_completion ;

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

print $_->{path} . "\n" for @matches ;

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

return unless @paths ;
	
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
		push @direct_matches, {path => $path_to_match, weight => 0, matches => 'directory under cwd'} ;
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
			my @directories = File::Spec->splitdir($directory) ;
			my $cumulated_path_weight = get_paths_weight($db, @directories) ;

			push @cwd_sub_directory_matches, {path => $directory, weight => 0, cumulated_path_weight => $cumulated_path_weight, matches => 'sub directory under cwd'} ;
			} 
		}
	
	@cwd_sub_directory_matches = sort {$b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{path} cmp $b->{path}} @cwd_sub_directory_matches ;
	
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


#------------------------------------------------------------------------------------------------------------------------

sub generate_bash_completion
{
	
=head2 [P]generate_bash_completion(@command_options)

The generated completion is in two parts:

A perl script used to generate  the completion (output on stdout) and a shell script that you must source (output on stderr).

 $> my_app -bash 1> my_app_perl_completion.pl 2> my_app_regiter_completion

Direction about how to use the completion scritp is contained in the generated script.

I<Arguments> - @command_options - list of the optionsthe command accepts

I<Returns> - Nothing - exits with status code B<1> after emitting the completion script on stdout

I<Exceptions> -  None - Exits the program.

=cut

my @command_options = @_ ;
my @options ;

use English;
use File::Basename ;
my ($basename, $path, $ext) = File::Basename::fileparse($PROGRAM_NAME, ('\..*')) ;
my $application_name =  $basename . $ext ;

local $| = 1 ;

my $complete_script =  <<"COMPLETION_SCRIPT" ;

#The perl script has to be executable and somewhere in the path.                                                         
#This script was generated using used your application name

#Add the following line in your I<~/.bashrc> or B<source> them:

_${application_name}_perl_completion()
{                     
local old_ifs="\${IFS}"
local IFS=\$'\\n';      
COMPREPLY=( \$(${application_name}_perl_completion.pl \${COMP_CWORD} \${COMP_WORDS[\@]}) );
IFS="\${old_ifs}"                                                       

return 1;
}        

complete -o default -F _${application_name}_perl_completion $application_name
COMPLETION_SCRIPT

print {*STDERR} $complete_script ;

print {*STDOUT} <<'COMPLETION_SCRIPT' ;
#! /usr/bin/perl                                                                       

=pod

I<Arguments> received from bash:

=over 2

=item * $index - index of the command line argument to complete (starting at '1')

=item * $command - a string containing the command name

=item * \@argument_list - list of the arguments typed on the command line

=back

You return possible completion you want separated by I<\n>. Return nothing if you
want the default bash completion to be run which is possible because of the <-o defaul>
passed to the B<complete> command.

Note! You may have to re-run the B<complete> command after you modify your perl script.

=cut

use strict;
use Tree::Trie;

my ($argument_index, $command, @arguments) = @ARGV ;

$argument_index-- ;
my $word_to_complete = $arguments[$argument_index] ;

my %top_level_completions = # name => takes a file 0/1
	(	
COMPLETION_SCRIPT

print {*STDOUT}  join("\n", @options) . "\n" ;
	
print {*STDOUT} <<'COMPLETION_SCRIPT' ;
	) ;
		
my %commands_and_their_options =
	(
COMPLETION_SCRIPT

print {*STDOUT} join("\n", @command_options) . "\n" ;

print {*STDOUT} <<'COMPLETION_SCRIPT' ;
	) ;
	
my @commands = (sort keys %commands_and_their_options) ;
my %commands = map {$_ => 1} @commands ;
my %top_level_completions_taking_file = map {$_ => 1} grep {$top_level_completions{$_}} keys %top_level_completions ;

my $command_present = 0 ;
for my $argument (@arguments)
	{
	if(exists $commands{$argument})
		{
		$command_present = $argument ;
		last ;
		}
	}

my @completions ;
if($command_present)
	{
	# complete differently depending on $command_present
	push @completions, @{$commands_and_their_options{$command_present}}  ;
	}
else
	{
	if(defined $word_to_complete)
		{
		@completions = (@commands, keys %top_level_completions) ;
		}
	else
		{
		@completions = @commands ;
		}
	}

if(defined $word_to_complete)
        {
	my $trie = new Tree::Trie;
	$trie->add(@completions) ;

        print join("\n", $trie->lookup($word_to_complete) ) ;
        }
else
	{
	my $last_argument = $arguments[-1] ;
	
	if(exists $top_level_completions_taking_file{$last_argument})
		{
		# use bash file completiong or we could pass the files ourselves
		#~ use File::Glob qw(bsd_glob) ;
		#~ print join "\n", bsd_glob('M*.*') ;
		}
	else
		{
		print join("\n", @completions)  unless $command_present ;
		}
	}

COMPLETION_SCRIPT

exit(0) ;

}


