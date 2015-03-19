
use strict ;
use warnings ;

package t::Jump ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(jump_test) ;
our $VERSION = '0.5' ;

use Test::Exception ;
use Test::Warn;
use Test::NoWarnings qw(had_no_warnings);
#use Test::Block qw($Plan);
use Test::Deep ;
use Test::More qw(no_plan) ;

use Cwd ;
use Test::MockModule ;
use Directory::Scratch ;
use File::Path::Tiny ;
use File::Spec ;
use Data::TreeDumper ;
use Data::TreeDumper::Utils qw(:all) ;
use Clone qw(clone) ;
use YAML ;

use App::Term::Jump ;


#------------------------------------------------------------------------------------------------------------------------

sub jump_test
{
my (%setup_arguments) = @_ ;

$setup_arguments{caller} = join(':', @{[caller()]}[1 .. 2]) ;

$setup_arguments{name} =~ s/ +/_/g ;

if(exists $setup_arguments{directories_and_db})
	{
	@setup_arguments{'temporary_directory_structure', 'db_start'} = get_directories_and_db($setup_arguments{directories_and_db}) ;
	delete $setup_arguments{directories_and_db} ;
	}

my $start_directory = cwd() ;
my $test_directory = cwd() ;
my $using_temporary_directory = 0 ;
my $temporary_database ;

# temporary test directory
if(exists $setup_arguments{temporary_directory_structure})
	{
	my $temporary_directory_root = File::Spec->tmpdir() . "/jump_test_$setup_arguments{name}_" ;
	my $allowed_characters_in_directory_name = ['a' .. 'z'] ;
	$test_directory = create_directory_structure($setup_arguments{temporary_directory_structure}, $temporary_directory_root, '1234', $allowed_characters_in_directory_name) ;

	chdir($test_directory) or die "Error: Can't cd to temporary directory: $!\n" ;
	$using_temporary_directory++ ;

	# database --------------------------------------------------

	$temporary_database = "$test_directory/temporary_jump_database" ;
	local $ENV{APP_TERM_JUMP_DB} = $temporary_database ;

	my @db_interpolated ;
	while (my ($k, $v) = each %{$setup_arguments{db_start}})
		{
		$k =~ s/TD/$test_directory/g ;
		$k =~ s/TEMPORARY_DIRECTORY/$test_directory/g ;
		push @db_interpolated, $k, $v ;
		}

	App::Term::Jump::write_db({@db_interpolated}) ;
	}

local $ENV{APP_TERM_JUMP_DB} = $temporary_database if exists $setup_arguments{temporary_directory_structure} ;

# configuration ----------------------------------------------

my $temporary_configuration ;
if(exists $setup_arguments{configuration})
	{ 
	$temporary_configuration = "$test_directory/temporary_jump_configuration" ;

	use File::Slurp ;
	File::Slurp::write_file($temporary_configuration, $setup_arguments{configuration}) ;
	}

local $ENV{APP_TERM_JUMP_CONFIG} = $temporary_configuration if(exists $setup_arguments{configuration}) ;
$setup_arguments{configuration} = App::Term::Jump::get_config() if(exists $setup_arguments{configuration}) ;

# tests -------------------------------------------------------

my $test_index = -1 ;
my $error ;

for my $test (@{$setup_arguments{tests}})
	{
	$test->{cd} =~ s/TD/$test_directory/g if exists $test->{cd} ;
	exists $test->{cd} ? chdir($test->{cd}) : chdir($test_directory) ;

	$test_index++ ;
	my $test_name = $test->{name} || '' ;

	die "Error: need 'command' or 'commands' fields in a test '$test_name::$test_index'" , DumpTree($test)
		if ! exists $test->{command} &&  ! exists $test->{commands} ;

 	if(exists $test->{command})
		{
	 	die "Error: can't have 'command' and 'commands' fields in a test '$test_name::$test_index'" if exists $test->{commands} ;
		$test->{commands} = [$test->{command}] ;
		delete $test->{command} ;
		}
	
	$test->{db_expected} = {map { my $key = $_ ; s/TD/$test_directory/g ; s/TEMPORARY_DIRECTORY/$test_directory/g ; $_ => $test->{db_expected}{$key} }  keys %{$test->{db_expected}}}
		if exists $test->{db_expected} ;

	$test->{captured_output_expected} = [map { s/TD/$test_directory/g ; s/TEMPORARY_DIRECTORY/$test_directory/g ; $_ }  @{$test->{captured_output_expected}}]
		if exists $test->{captured_output_expected} ;

	$test->{matches_expected} = [map { s/TD/$test_directory/g ; s/TEMPORARY_DIRECTORY/$test_directory/g ; $_ }  @{$test->{matches_expected}}]
		if exists $test->{matches_expected} ;

	my ($weight, $cumulated_path_weight, @matches) ;

	use IO::Capture::Stdout;
	my $capture = IO::Capture::Stdout->new();
	$capture->start();

	if(exists $test->{warnings_expected})
		{
		warnings_like
		        {
			for my $command (@{ $test->{commands} })
				{
				$command =~ s/^\s+// ;
				$command =~ s/TD/$test_directory/g ;
				$command =~ s/TEMPORARY_DIRECTORY/$test_directory/g ;

				eval ('(@matches) = App::Term::Jump::' . $command) ;
				$test->{weight} = $weight = $matches[0]{weight} if @matches ;
				$test->{weight_path} = $cumulated_path_weight = $matches[0]{cumulated_path_weight} if @matches ;
				$test->{matches} = \@matches ;

				die $@ if $@ ;
				}

	        	} $test->{warnings_expected}, "warnings expected '$test_name::$test_index'" ;
		}
	else
		{
		for my $command (@{ $test->{commands} })
			{
			$command =~ s/^\s+// ;
			$command =~ s/TD/$test_directory/g ;
			$command =~ s/TEMPORARY_DIRECTORY/$test_directory/g ;

			eval ('(@matches) = App::Term::Jump::' . $command) ;
			$test->{weight} = $weight = $matches[0]{weight} if @matches ;
			$test->{weight_path} = $cumulated_path_weight = $matches[0]{cumulated_path_weight} if @matches ;
			$test->{matches} = \@matches ;

			die $@ if $@ ;
			}
		}

	$capture->stop() ;
	$test->{captured_output} = [map {chomp ; $_} $capture->read()] if exists $test->{captured_output_expected} ;
	
	$test->{db_after_command} = App::Term::Jump::read_db() ;

	do { cmp_deeply($test->{captured_output}, $test->{captured_output_expected}, "output-$setup_arguments{name}-$test_name::$test_index") or $error++}
		if exists $test->{captured_output_expected} ;

	do 
		{
		 cmp_deeply
			(
			[ map{$_->{path}} @matches],
			$test->{matches_expected},
			"matches-$setup_arguments{name}-$test_name::$test_index"
			) or $error++
		}
		if exists $test->{matches_expected} ;

	do { is($weight, $test->{weight_expected}, "weight-$setup_arguments{name}-$test_name::$test_index") or $error++}
		if exists $test->{weight_expected} ;
	
	do { is($cumulated_path_weight, $test->{weight_path_expected}, "weight_path-$setup_arguments{name}-$test_name::$test_index") or $error++}
		if exists $test->{weight_path_expected} ;
	
	do { cmp_deeply($test->{db_after_command}, $test->{db_expected}, "DB contents-$setup_arguments{name}-$test_name::$test_index") or $error++ }
		if exists $test->{db_expected} ;
  
	if($error)
		{
		$setup_arguments{test_failed_index} = $test_index ;

		splice @{$setup_arguments{tests}}, $test_index + 1 ;

		#TODO: check if previous test->db_after_command is the same as current
		# uncluter, and make it clear it it the same, otherwise make it clear it changed

		diag DumpTree \%setup_arguments, "test: $setup_arguments{name}",
			DISPLAY_ADDRESS => 0, 
		        FILTER => \&first_nsort_last_filter,
			FILTER_ARGUMENT =>
				{
				AT_START_FIXED => ['name', 'commands'],
				#AT_END => [qr/AB/],
				} ;

        	#diag "test commands: pushd $test_directory ; APP_TERM_JUMP_DB='./database' jump_test --show_database xxx $test_directory\n" ;
		#diag "tree $test_directory\n" ;
		#diag "cat $test_directory/temporary_jump_database" ;
	
		last ;
		}
	else
		{
		# uncluter output 
		$setup_arguments{tests}[$test_index -1] = 'ok' unless $test_index == 0 ;
		$test = {db_after_command => $test->{db_after_command}} ;
		}
	}

chdir($start_directory) ;
File::Path::Tiny::rm($test_directory) if $using_temporary_directory && ! $error ;
}

sub create_directory_structure
{
my ($directory_structure, $temporary_directory_root, $template, $allowed_characters_in_directory_name) = @_ ;

my $temp_directory = create_temporary_directory($temporary_directory_root, $template, $allowed_characters_in_directory_name) or die "Error: Can't create temporary directory\n" ;

_create_directory_structure($directory_structure, $temp_directory) ;

return $temp_directory ;
}

sub _create_directory_structure
{
my ($directory_structure, $start_directory) = @_ ;
 
while( my ($entry_name, $contents) = each %{$directory_structure})
        {
        for($contents)
                {
                'HASH' eq ref $_ and do
                        {
                        File::Path::Tiny::mk("$start_directory/$entry_name") or die "Could not make directory '$start_directory/$entry_name': $!" ;
                        _create_directory_structure($contents, "$start_directory/$entry_name") ;
                        last ;
                        } ;
                         
                die "invalid element '$start_directory/$entry_name' in tree structure\n" ;
                }
        }
}

my $temporary_directory_increment = 0 ;

sub create_temporary_directory
{
my ($temporary_directory_root, $template, $allowed_characters_in_directory_name) = @_ ;

$temporary_directory_increment++ ;

my $dir ;
my $number_of_allowed_characters = @{$allowed_characters_in_directory_name} ;

for (1 .. 500)
	{
	my $template_try = $template =~ s/./$allowed_characters_in_directory_name->[int(rand($number_of_allowed_characters))]/ger ; 
	my $path = $temporary_directory_root . '_' . $$ . '_' . $temporary_directory_increment . '_' . $template_try ;

	if(File::Path::Tiny::mk($path))
		{
		$dir = $path ;
		last ;
		} 
	}

die "Could not create temporary directory '$temporary_directory_root': $!" unless defined $dir ;

return $dir ;
}


sub get_directories_and_db
{
my ($yaml) = @_ ;

my %db_paths ;

my $get_db_paths = sub
	{
	my ($structure, undef, $path) = @_ ;

	if('HASH' eq ref $structure)
		{
		if(exists $structure->{in_db})
			{
			$path =~ s[\{'(.+?)'\}][$1/]g;
			$path = 'TEMPORARY_DIRECTORY/' . $path ;
			$path =~ s[/$][] ;

			$db_paths{$path} = $structure->{in_db} ;

			delete $structure->{in_db} ;
			}
		}

	return(Data::TreeDumper::DefaultNodesToDisplay($structure)) ;
	} ;

$yaml = "---\n$yaml\n" ;
my $directory_structure = Load($yaml) ;

DumpTree $directory_structure, 'munged', NO_OUTPUT => 1, FILTER => $get_db_paths ;

#diag "YAML\n$yaml\n";
#diag DumpTree $directory_structure, 'Directories' ;
#diag DumpTree \%db_paths, 'DB' ;

return ($directory_structure, \%db_paths) ;
}


1 ;

