
package App::Term::Jump ;

use strict ;
use warnings ;

use File::Basename ;
use File::Spec ;
use Getopt::Long;
use File::Find::Rule ;
use File::HomeDir ;
use Cwd ;
use Data::TreeDumper ;
use Tree::Trie;

our $VERSION = '0.04' ;

=head1 NAME 

App::Term::Jump - searcheable database of often visited directories

=head1 DESCRIPTION

A utility to navigate your filesystem. It can ither be used directly on the 
command line or integrated with Bash.

=cut

#------------------------------------------------------------------------------------------------------------------------

$|++ ;

use Readonly ;

Readonly my $FIND_FIRST => 0 ;
Readonly my $FIND_ALL => 1 ;

Readonly my $SOURCE_OR_PATH => 0 ;
Readonly my $PATH => 1 ;

#------------------------------------------------------------------------------------------------------------------------

sub run
{
my (@command_line_arguments) = @_ ;

my ($options, $command_line_arguments) = parse_command_line(@command_line_arguments) ;

show_help() if($options->{help}) ;

warn "\nJump: Error: no command given" unless 
	grep {defined $options->{$_}} qw(search add remove remove_all show_database show_configuration_files version complete) ;

return (execute_commands($options, $command_line_arguments), $options) ;
}

sub execute_commands
{
# warning, if multipe commands are given on the command line, jump will run them at the same time

my ($options, $command_line_arguments) = @_ ;

my $results = [] ;

remove_all($options, $command_line_arguments) if($options->{remove_all}) ;
remove($options, $command_line_arguments) if($options->{remove}) ;

add($options, $command_line_arguments) if($options->{add}) ;

$results = complete($options, $command_line_arguments) if($options->{complete}) ;
$results = search($options, $command_line_arguments) if($options->{search}) ;

show_database($options) if($options->{show_database}) ;
show_configuration_files($options) if($options->{show_configuration_files}) ;
show_version() if($options->{version}) ;

return $results ;
}

#------------------------------------------------------------------------------------------------------------------------

sub parse_command_line
{
local @ARGV = @_ ;

my %options = (ignore_path => []) ;

$options{db_location} = defined $ENV{APP_TERM_JUMP_DB} ? $ENV{APP_TERM_JUMP_DB} : home() . '/.jump_db' ;
$options{config_location} = defined $ENV{APP_TERM_JUMP_CONFIG} ? $ENV{APP_TERM_JUMP_CONFIG} : home() . '/.jump_config'  ;

%options = ( %options, %{ get_config($options{config_location}) } ) ;


die 'Error parsing options!' unless 
	GetOptions
                (
		'search' => \$options{search},
		'file=s' => \$options{file},

		'complete' => \$options{complete},

		'a|add' => \$options{add},
		'r|remove' => \$options{remove},
		'remove_all' => \$options{remove_all},

		's|show_database' => \$options{show_database},

		'show_configuration_files' => \$options{show_configuration_files},
		'v|V|version' => \$options{version},
                'h|help' => \$options{help}, 

		'ignore_path=s' => $options{ignore_path},

		'q|quote' => \$options{quote},
		'ignore_case' => \$options{ignore_case},
		'no_direct_path' => \$options{no_direct_path},
		'no_sub_cwd' => \$options{no_sub_cwd},
		'no_sub_db' => \$options{no_sub_db},

		'd|debug' => \$options{debug},
                ) ;
	
# broken bash completion gives use file regext with quotes from command line!
$options{file} = $1 if(defined $options{file} && $options{file} =~ /^(?:'|")(.*)(?:'|")$/) ;

# remove trailing slash, except for root
@ARGV = map {s[(.)/$][$1]; $_} @ARGV ;

return (\%options, \@ARGV) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub get_config
{
my ($config_location) = @_ ;
my $config = {} ;

if(-f $config_location)
	{
	unless ($config = do $config_location) 
		{
		die "couldn't parse '$config_location': $@" if $@;
		die "couldn't do '$config_location': $!"    unless defined $config;
		die "couldn't run '$config_location'"       unless $config;
		}
	}
else
	{
	# write a default configuration file
	open my $new_config_fh, '>', $config_location or die "Jump: Can't create default config in '$config_location': $!" ;
	
	print $new_config_fh <<EOC ;

{
ignore_path => [] , # paths that will not match. string or qr
black_listed_directories => [] , # pths that will not be added to the db. string or qr

ignore_case => 0, 	#case insensitive search and completion

no_direct_path => 0, 	#ignore directories directly under cwd
no_sub_cwd => 0, 	#ignore directories and sub directories under cwd
no_sub_db => 0, 	#ignore directories under the database entries
} ;

EOC
	}
		
return
	{
	ignore_path => [], 	# path that will not match
	black_listed_directories => [] , #paths that will not be added to the db

	ignore_case => 0, 	#case insensitive search and completion
	no_direct_path => 0, 	#ignore directories directly under cwd
	no_sub_cwd => 0, 	#ignore directories and sub directories under cwd
	no_sub_db => 0, 	#ignore directories under the database entries


	%{$config},
	} ;
}

#------------------------------------------------------------------------------------------------------------------------

sub complete
{
my ($options, $search_arguments) = @_ ;
my ($matches) = _complete($options, $search_arguments) ;

print_matches($options, $SOURCE_OR_PATH, $matches) ;

return $matches ;
}

sub _complete
{
my ($options, $search_arguments) = @_ ;

my ($matches) = find_closest_match($options, $FIND_ALL, $search_arguments) ;

$matches = directory_contains_file($options, $matches) ;

return $matches ;
}

#------------------------------------------------------------------------------------------------------------------------

sub search
{
my ($options, $search_arguments) = @_ ;

my ($matches) = find_closest_match($options, $FIND_FIRST, $search_arguments) ;

$matches = directory_contains_file($options, $matches) ;

print_matches($options, $PATH, [$matches->[0]]) if @{$matches} ;

return $matches ;
}

#------------------------------------------------------------------------------------------------------------------------

sub print_matches
{
my ($options, $field, $matches) = @_;

for (@{$matches})
	{
	my $result = $field == $PATH ? $_->{path} : ($_->{source} || $_->{path}) ;
		
	my $quotes = $options->{quote} ? '"' : '' ;

	print "$quotes$result$quotes\n" ;
	}

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub find_closest_match
{
my ($options, $find_all, $paths) = @_ ;

my @paths = @{ $paths } ;

return [] unless @paths ;

my $cwd = cwd() ;

my $path_to_match = join('.*', @paths) ;
my $end_directory_to_match = $paths[-1] ;
my $path_to_match_without_end_directory =  @paths > 1 ? join('.*', @paths[0 .. $#paths-1]) : qr// ;
$path_to_match_without_end_directory =~ s[^\./][$cwd] ;

if($paths[0] =~ m[^/])
	{
	$path_to_match = "^$path_to_match" ;
	$path_to_match_without_end_directory = "^$path_to_match_without_end_directory" ;
	}	
	
warn DumpTree
	{
	end_directory => $end_directory_to_match,
	path => $path_to_match_without_end_directory,
	paths => \@paths,
	} if $options->{debug} ;

my %matches ;

# find possible approximations and jumps, including minor path jumps

my (@direct_matches, @directory_full_matches, @directory_partial_matches, @path_partial_matches, @cwd_sub_directory_matches, @sub_directory_matches) ;

my $db = read_db($options) ;
	
# matching direct paths
if(1 == @paths && !$options->{no_direct_path})
	{
	warn "looking for direct matches\n" if $options->{debug} ;
	my $path_to_match = $paths[0] ;

	if($path_to_match =~ m[^/] && -d $path_to_match)
		{
		warn "matches full path in file system: $path_to_match\n" if $options->{debug} ;

		push @direct_matches, {path => $path_to_match, weight => 0,cumulated_path_weight => 0,  matches => 'full path in file system'} 
			unless exists $matches{$path_to_match} ;

		$matches{$path_to_match}++ ;
		}
	elsif(-d $cwd . '/' . $path_to_match)
		{
		warn "matches directory under cwd: $path_to_match\n" if $options->{debug} ;

		$path_to_match =~ s[^\./+][] ;
		$path_to_match =~ s[^/+][] ;
		
		push @direct_matches, {path => $path_to_match, weight => 0, cumulated_path_weight => 0, matches => 'directory under cwd'} 
			unless exists $matches{$cwd . '/' . $path_to_match} ;
		
		$matches{$cwd . '/' . $path_to_match}++ ;
		}
	}

my $ignore_case = $options->{ignore_case} ? '(?i)' : '' ;

#matching directories in database
for my $db_entry (sort keys %{$db})
	{
	warn "looking for database  matches\n" if $options->{debug} ;

	my @directories = File::Spec->splitdir($db_entry) ;
	my $db_entry_end_directory = $directories[-1] ;

	my $weight = $db->{$db_entry} ;
	my $cumulated_path_weight = get_paths_weight($db, @directories) ;	

	if($db_entry_end_directory =~ /$ignore_case^$end_directory_to_match$/)
		{
		if($db_entry =~  /$ignore_case$path_to_match/)
			{
			warn "matches end directory in db entry: $db_entry\n" if $options->{debug} ;

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
			warn "matches part of end directory in db entry: $db_entry\n" if $options->{debug} ;

			push @directory_partial_matches,
				{ path => $db_entry, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'part of end directory in db entry'} 
					unless exists $matches{$db_entry} ;

			$matches{$db_entry}++ ;
			}
		}
	elsif(my ($part_of_path_matched) = $db_entry =~ m[$ignore_case(.*$path_to_match[^/]*)])
		{
		warn "matches part of path in db entry: $db_entry\n" if $options->{debug} ;
		
		push @path_partial_matches, 
			{ path => $part_of_path_matched, source => $db_entry, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'part of path in db entry'} 
					unless exists $matches{$db_entry} ;
			
		$matches{$db_entry}++ ;
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
	
# matching sub directories under cwd 
if(! $options->{no_sub_cwd} && ($find_all || 0 == keys %matches))
	{
	my @discard_rules = map { File::Find::Rule->new->directory->name(qr/$_/)->prune->discard } @{$options->{ignore_path}} ; 
	my $search = File::Find::Rule->or(@discard_rules, File::Find::Rule->directory) ;

	for my $directory ($search->in($cwd))
		{
		next if $directory eq $cwd ;

		warn "looking for matches in cwd sub directory '$directory'\n" if $options->{debug} ;

		my $sub_directory = $directory =~ s[^$cwd][]r ;
		my $cwd_path_to_match = $path_to_match =~ s[^\./][/]r ;

		if(my ($part_of_path_matched) = $sub_directory =~  m[$ignore_case(.*$cwd_path_to_match.*?)(/|$)])
			{
			warn "matches sub directory under cwd: $directory\n" if $options->{debug} ;

			my @directories = File::Spec->splitdir($part_of_path_matched) ;
			my $cumulated_path_weight = get_paths_weight($db, @directories) ;

			push @cwd_sub_directory_matches, {path => "$cwd$part_of_path_matched", source => $directory, weight => 0, cumulated_path_weight => $cumulated_path_weight, matches => 'sub directory under cwd'}
				unless exists $matches{$directory} ;

			$matches{$directory}++ ;
			} 
		}
	
	@cwd_sub_directory_matches = sort {$b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{source} cmp $b->{source}} @cwd_sub_directory_matches ;
	}

# matching directories under database entries
if(! $options->{no_sub_db} && ($find_all || 0 == keys %matches))
	{
	for my $db_entry (sort {$db->{$b} <=> $db->{$a} || $a cmp $b } keys %{$db})
		{
		my $weight = $db->{$db_entry} ;
		my $cumulated_path_weight = get_paths_weight($db, File::Spec->splitdir($db_entry)) ;	

		my @discard_rules = map { File::Find::Rule->new->directory->name(qr/$_/)->prune->discard } @{$options->{ignore_path}} ; 
		my $search = File::Find::Rule->or(@discard_rules, File::Find::Rule->directory) ;

		for my $directory ($search->in($db_entry))
			{
			next if $directory eq $db_entry ;
			warn "looking for database matches in sub directory '$directory'\n" if $options->{debug} ;

			if(my ($part_of_path_matched) = $directory =~  m[$ignore_case(.*$path_to_match.*?)(/|$)])
				{
				warn "matches sub directory under database entry: $directory\n" if $options->{debug} ;
				push @sub_directory_matches, 
					{path => $part_of_path_matched, source => $directory, weight => $weight, cumulated_path_weight => $cumulated_path_weight, matches => 'sub directory under a db entry'} 
						unless exists $matches{$directory} ;

				$matches{$directory}++ ;
				} 
			}
		}  

	@sub_directory_matches = 
		sort {$b->{weight} <=> $a->{weight} || $b->{cumulated_path_weight} <=> $a->{cumulated_path_weight} || $a->{source} cmp $b->{source}} 
			@sub_directory_matches ;
	}

return [@direct_matches, @directory_full_matches, @directory_partial_matches, @path_partial_matches, @cwd_sub_directory_matches, @sub_directory_matches] ;
}
				
#------------------------------------------------------------------------------------------------------------------------

sub directory_contains_file
{
my ($options, $directories) = @_ ;
my $file_regexp = $options->{file} ;

return $directories unless $file_regexp ;

return
	[
	grep
		{
		my $source = $_->{source} || $_->{path} ; 

		my @files = File::Find::Rule->maxdepth(1)->file()->name($file_regexp)->in($source) ;

		if($options->{debug})
			{
			warn "Checking option --file '$file_regexp' for directory '$source' found: " . scalar(@files) . " \n" ;
			warn "\t$_\n" for @files ;
			}

		@files ;
		}
		@{ $directories } 
	] ;

}
 
#------------------------------------------------------------------------------------------------------------------------

sub get_paths_weight
{
my ($db, @directories) = @_ ;

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
my ($options, $arguments) = @_ ;

my ($weight, $path) = check_weight_and_path(@{$arguments}) ;

my $db = read_db($options) ;

delete $db->{$path} ;

write_db($options, $db) ;

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub add
{
my ($options, $arguments) = @_ ;

my ($weight, $path) = check_weight_and_path(@{$arguments}) ;

if(! is_blacklisted($options, $path))
	{
	my $db = read_db($options) ;

	if(exists $db->{$path})
		{
		$db->{$path} += $weight ;
		} 
	else
		{
		$db->{$path} = $weight ;
		}

	write_db($options, $db) ;
	}

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub remove_all
{
my %new_db ;

my ($options, $arguments) = @_ ;

my @remove_arguments = @{ $arguments } ;

if(0 == @remove_arguments)
	{
	# no argument, remove all entries
	}
else
	{
	my $db = read_db($options) ;

	for my $key (keys %{$db})
		{
		my $delete_key = 0 ;

		for my $delete_regex (@remove_arguments)
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

write_db($options, \%new_db) ;

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub show_database
{
my ($options) = @_ ;

my $db = read_db($options) ;

for my $path (sort {$db->{$b} <=> $db->{$a} || $a cmp $b} keys %{$db} )
	{
	print "$db->{$path} $path\n" ;
	}

return ;
}


#------------------------------------------------------------------------------------------------------------------------

sub show_configuration_files
{
my ($options) = @_ ;

print "$options->{db_location}\n" ;
print "$options->{config_location}\n" ;

return ;
}


#------------------------------------------------------------------------------------------------------------------------

sub show_version
{
print "Jump version $VERSION\n" ;

return ;
}

#------------------------------------------------------------------------------------------------------------------------

sub read_db
{
my ($options) = @_ ;
my %db ;

my $regex = qr/(\d+)\ (.*)/ ;

use IO::File ;

my $db_fh = IO::File->new() ;

if($db_fh->open($options->{db_location}, 'r'))
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
else
	{
	die "Jump: Can't open database '$options->{db_location}' for reading! $!" ;
	}

return \%db ;
}

#------------------------------------------------------------------------------------------------------------------------

sub write_db
{
my ($options, $db) = @_ ;

open my $db_fh, '>', $options->{db_location} or die "Jump: Can't open database '$options->{db_location}' for writing! $!" ;

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
	elsif('..' eq $path)
		{
		$path = Cwd::realpath(File::Spec->updir);
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
my ($options, $path) = @_ ;

return grep {$path =~ $_} @{ $options->{black_listed_directories} } ; 
}

#------------------------------------------------------------------------------------------------------------------------

sub show_help
{ 
#print STDERR `$ENV{SHELL} -c "man <(pod2man $0)"` or warn 'Can\'t display help!' ; ## no critic (InputOutput::ProhibitBacktickOperators)
system($ENV{SHELL}, '-c', "man <(pod2man $0)") or warn 'Can\'t display help!' ; ## no critic (InputOutput::ProhibitBacktickOperators)
exit(1) ;
}

#------------------------------------------------------------------------------------------------------------------------

sub do_bash_completion
{

my $ignore = <<'IGNORE' ;

#=pod

I<Arguments> received from bash:

#=over 2

#=item * $index - index of the command line argument to complete (starting at '1')

#=item * $command - a string containing the command name

#=item * \@arguments - list of the arguments typed on the command line

#=back

#=cut

IGNORE

my ($argument_index, $command, @arguments) = @ARGV ;

$argument_index-- ;
my $word_to_complete = $arguments[$argument_index] ;

if(defined $word_to_complete && $word_to_complete =~ /^-/)
        {
	my ($option_separator) = $word_to_complete =~ m/^\s*(-+)/ ;
	$word_to_complete =~ s/^\s*-*// ;
	$word_to_complete =~ s/\s+$// ;

        my $trie = new Tree::Trie;
        
	$trie->add( 
		qw(
		search
		file
		complete
		a add
		r remove
		remove_all
		s show_database
		show_setup_files

		ignore_path
		ignore_case
		no_direct_path
		no_sub_cwd
		no_sub_db

		v version
		h help
		)) ;

        print join("\n", map { "$option_separator$_" } $trie->lookup($word_to_complete) ) ;
        }
else
        {
	my %with_completion = map {("-$_" => 1, "--$_" => 1)}
		qw(
		search
		complete
		remove
		remove_all 
		) ;
	
	my $do_completion = grep { exists $with_completion{$_} } @arguments ;
	
	if($do_completion)
		{
		#$App::Term::Jump::debug++ ;

		my ($options, $search_arguments) = parse_command_line(@arguments) ;

		if($options->{remove})
			{
			#allow completion of db entries only

			$options->{ignore_case} = 0 ;
			$options->{no_direct_path}++;
			$options->{no_sub_cwd}++ ;
			$options->{no_sub_db}++ ;

			@arguments = ('.') if 1 == @arguments ; # force completion to whole db if no arguments are given
			}

		my @completions = @{_complete($options, $search_arguments)} ;

		#print STDERR DumpTree {command => $command, index => $argument_index, options => $options, arguments => $search_arguments, completions => \@completions} ;

		if(0 == @completions)
			{
			# no completion
			}
		elsif(1 == @completions)
			{
			print "1 db match:\n" ;
			print (($completions[0]{source} || $completions[0]{path}) . "\n") ;

			if(1 == @{$search_arguments})
				{
				my ($path, $name) = $search_arguments->[0] =~ m[^(.*/)?(.*)] ;
				$path ||= '.' ;
				$name ||= '' ;

				print "$_/\n" for (File::Find::Rule->maxdepth(1)->directory()->name("$name*")->in($path)) ;
				}
			}
		else
			{
			print scalar(@completions) . " db matches:\n" ;
			print (($_->{source} || $_->{path}) . "\n") for(@completions) ;

			if(1 == @{$search_arguments})
				{
				my ($path, $name) = $search_arguments->[0] =~ m[^(.*/)?(.*)] ;
				$path ||= '.' ;
				$name ||= '' ;

				print "$_/\n" for (File::Find::Rule->maxdepth(1)->directory()->name("$name*")->in($path)) ;
				}
			}
		}
	}

return ;
}

#------------------------------------------------------------------------------------------------------------------------

1 ;


