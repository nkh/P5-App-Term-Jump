#! /usr/bin/perl

use App::Term::Jump ;

=pod

I<Arguments> received from bash:

=over 2

=item * $index - index of the command line argument to complete (starting at '1')

=item * $command - a string containing the command name

=item * \@arguments - list of the arguments typed on the command line

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

if(defined $word_to_complete && $word_to_complete =~ /^-/)
        {
	my ($option_separator) = $word_to_complete =~ m/^\s*(-+)/ ;
	$word_to_complete =~ s/^\s*-*// ;
	$word_to_complete =~ s/\s+$// ;

        my $trie = new Tree::Trie;
        
	$trie->add( 
		qw(
		search
		complete
		a add
		r remove
		remove_all
		s show_database
		show_setup_files
		v version
		h help
		generate_bash_completion
		)) ;

        print join("\n", map { "$option_separator$_" } $trie->lookup($word_to_complete) ) ;
        }
else
        {
	# use jump command line parser
	# complete based on command
		qw(
		search
		complete
		remove
		
		add  bash completion
		
		below no completion:
		remove_all 
		show_database
		show_setup_files
		version
		help
		generate_bash_completion
		) ;


#	@arguments = grep { ! /^-/ } @arguments ;

	# no input do nothing, thus bash completion

	#$App::Term::Jump::debug++ ;
	my @completions = App::Term::Jump::run(@arguments) ;

	#use Data::TreeDumper ;
	#print STDERR DumpTree {command => $command, index => $argument_index, arguments => \@arguments, completions => \@completions} ;

	if(0 == @completions)
		{
		# no completion
		}
	elsif(1 == @completions)
		{
		print "1 match\n$completions[0]{path}" ;
		}
	else
		{
		print scalar(@completions) . " matches:\n" ;
		print $_->{path} . "\n" for @completions ;
		}

	}

