use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	NAME              => 'Socket::More',
	VERSION_FROM      => 'lib/Socket/More.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
	PREREQ_PM         => {
		'Data::Combination'=>0,
		'Test::Deep'=>0,
		'Sort::Key'=>0,
		'Net::IP'=>0
	}, # e.g., Module::Name => 1.1
	MIN_PERL_VERSION=>"v5.36.0",
	TEST_REQUIRES	=>{
		'Test::Deep'=>0
	},
	ABSTRACT_FROM     => 'lib/Socket/More.pm', # retrieve abstract from module
	AUTHOR            => 'Ruben Westerberg <drclaw@mac.com>',
	LICENSE           => 'mit',
	LIBS              => [''], # e.g., '-lm'
	DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
	INC               => '-I.', # e.g., '-I. -I/usr/include/other'
	# Un-comment this if you add C files to link with later:
	# OBJECT            => '$(O_FILES)', # link all the C files too
);
if  (eval {require ExtUtils::Constant; 1}) {
	# If you edit these definitions to change the constants used by this module,
	# you will need to use the generated const-c.inc and const-xs.inc
	# files to replace their "fallback" counterparts before distributing your
	# changes.
	my @names = (qw());
	ExtUtils::Constant::WriteConstants(
		NAME         => 'Socket::More',
		NAMES        => \@names,
		DEFAULT_TYPE => 'IV',
		C_FILE       => 'const-c.inc',
		XS_FILE      => 'const-xs.inc',
	);

}
else {
	use File::Copy;
	use File::Spec;
	foreach my $file ('const-c.inc', 'const-xs.inc') {
		my $fallback = File::Spec->catfile('fallback', $file);
		copy ($fallback, $file) or die "Can't copy $fallback to $file: $!";
	}
}
