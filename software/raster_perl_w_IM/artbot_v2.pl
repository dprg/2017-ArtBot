#!/usr/bin/perl

# artbot.pl 
# ver 1.0
# 03 Mar 2017
# Copyright 2017 Steve Rainwater
# Licensed under the terms of the GNU GPL v3 or newer

# usage:
# artbot.pl inputimage.jpg

use Image::Magick;

# parameters 
my $width = 264;    # should be multiple of 132
my $height = 264;   # should be multiple of 132
my $colors = 4;
my $pixperdip = 20;
my $x_origin = 8;
my $y_origin = 187;
my $x_inc = .5;     # 132 / $width
my $y_inc = .5;     # 132 / $height

# set force_well to 0 and well number is incremented to match color
# e.g. color layer 1 gcode file uses well #1, layer 2 uses well #2, etc
# set force well to a value of 1 thru 5 and all gcode files use that well
my $force_well = 0;

my $gcode_feedrate = 'F5000';
my $gcode_brush_up_z = 'Z13';
my $gcode_brush_dn1_z = 'Z8.4';
my $gcode_brush_dn2_z = 'Z8.0';
my $gcode_waterx = 'X60'; # 'X160'; # hardcode to X value of well location
my $gcode_watery = 'Y28';
# end parameters (don't change anything below this line)

my $input_file = $ARGV[0];
my $base_file = $input_file;
$base_file =~ s/\..*+$//;
print "\n$base_file";

# init and load input file
my $p = new Image::Magick;
print $p->Read($input_file);
print "\n";

# display input stats
print "\nInput width: " . $p->Get('width');
print "\nInput height: " . $p->Get('height');
print "\nInput colors: " . $p->Get('depth') . ' bit depth';
print "\nInput colors: " . $p->QuantumDepth . ' quantum depth';
print "\nInput colors: " . $p->Get('colors') . ' colors';

# resize and requantize the input image
print "\n\nresizing, requantizing...\n";
$p->AdaptiveResize(geometry=>"$width" . 'x' . "$height", width=>$width, height=>$height);
$p->Posterize(levels=>3, dither=>'True');
$p->Quantize(colors=>$colors, dither=>'True', global=>'True', treedepth=>8);

# display output stats
print "\nOutput width: " . $p->Get('width');
print "\nOutput height: " . $p->Get('height');
print "\nOutput colors: " . $p->Get('depth') . ' bit depth';
print "\nOutput colors: " . $p->QuantumDepth . ' quantum depth';
print "\nOutput colors: " . $p->Get('colors') . ' colors';

# write full color output image
# todo - parse input filename and append '-64x64' and PNG ext
my $outfile = $base_file . '-out-' . $width . 'x' . $height . '.png';
$p->Write(filename=>$outfile,compression=>'None');

# get color palette
my @hist_data = $p->Histogram;
my @hist_entries;
while(@hist_data) {
    my ($r, $g, $b, $a, $count) = splice @hist_data, 0, 5;
    push @hist_entries, {
	r => $r >> 8,
	g => $g >> 8,
	b => $b >> 8,
	a => $a >> 8,
	count => $count,
    };
}

# sort color palette by luminance
@hist_entries = sort {
  ($b->{r} * 0.299)+($b->{g}*0.587)+($b->{b}*0.114)
  <=>
  ($a->{r} * 0.299)+($a->{g}*0.587)+($a->{b}*0.114)
} @hist_entries;

print "\n\nSorted color pallete:";
foreach (@hist_entries) {
    printf ("\nRGB = %03i %03i %03i (0x%02x%02x%02x) Count = %i",
	$_->{r}, $_->{g}, $_->{b},
	$_->{r}, $_->{g}, $_->{b},
	$_->{count});
}

# loop through colors
print "\n\nGenerating g-code by color layer...";
my $n = 1;
foreach (@hist_entries) {
    my $c = $_->{r} . $_->{g} . $_->{b};

    # generate text description for this layer
    my $layercomment = 
	sprintf ("image: %s color: %03i %03i %03i (0x%02x%02x%02x)",
	$base_file,
	$_->{r}, $_->{g}, $_->{b},
	$_->{r}, $_->{g}, $_->{b},
	$_->{count});

    # open file
    my $gfile = $base_file . '-' . $n . '.gcode';
    print "\nDumping " . $layercomment . ' to ' . $gfile;
    open(my $fh, '>', $gfile) or die "\nCould not open file: $gfile $!\n";
    
    # output g-code header
    print $fh "; g-code for $layercomment (using well #$n)\n";
    gcode_header($fh);

    # prep brush
    gcode_dip_water($fh);
    gcode_dip_paint($fh,$n);

    # count pixels painted since last tip
    my $pixpainted = 0;

    # do for each pixel in each row of image
    for(my $y=0; $y<$height; $y++) {
	for(my $x=0; $x<$width; $x++) {
	    (my $r,$g,$b,$a) = split /,/, $p->Get("Pixel[$x,$y]");
	    my $pixc = $r >> 8 . $g >> 8 . $b >> 8;
	    if($c ne $pixc) {
		print $fh "; $x, $y - skip\n";
		next;
	    } else {
		print $fh "; $x, $y - paint\n";
		gcode_stroke($fh,$x,$y);
		$pixpainted++;
		if($pixpainted >= $pixperdip) {
		    gcode_dip_water($fh);
		    gcode_dip_paint($fh,$n);
		    $pixpainted = 0;
		}
	    }
	}
    }

    # spit out g-code footer stuff
    gcode_footer($fh);
    
    # close file
    close $fh;
    $n++;
}


print "\n\n";

# print a brush stroke at desired pixel
sub gcode_stroke {
    my $fh = shift;
    my $x = shift || 0;
    my $y = shift || 0;
    
    # calculate pixel coordinates from image size
    my $ulx = $x_origin + ($x * $x_inc);
    my $uly = $y_origin - ($y * $y_inc);
    my $lrx = $ulx + $x_inc;
    my $lry = $uly - $y_inc;

    # do the stroke stuff
    print $fh <<"EOT";
; start stroke
G1 X$ulx Y$uly $gcode_brush_up_z $gcode_feedrate ; hover
G1 X$ulx Y$uly $gcode_brush_dn1_z $gcode_feedrate ; start stroke
G1 X$lrx Y$lry $gcode_brush_dn2_z $gcode_feedrate ; finish stroke
G1 X$lrx Y$lry $gcode_brush_up_z $gcode_feedrate ; hover
; end stroke
EOT

}

#  print common g-code for dipping brush in water
sub gcode_dip_water {
    my $fh = shift;

    print $fh <<"EOT";
; get water
G1 $gcode_waterx $gcode_watery Z30 $gcode_feedrate ; raise brush over water tank
G1 $gcode_waterx $gcode_watery Z15 $gcode_feedrate ; dip brush in water
G1 $gcode_waterx $gcode_watery Z30 $gcode_feedrate ; raise brush over water tank
; end of get water
EOT

}

# print commong g-code for dipping brush in paint
sub gcode_dip_paint {
    my $fh = shift;
    my $w = shift || 1;
    if($force_well > 0) { $w = $force_well; }
    my %well = (
                1 => 'X10  Y28',
                2 => 'X35  Y28',
                3 => 'X60  Y28',
                4 => 'X85  Y28',
                5 => 'X105 Y28',
                6 => 'X130 Y28'
               );

    print $fh <<"EOT";
; get paint
G1 $well{$w} Z30 $gcode_feedrate ; move over well
G1 $well{$w} Z16 $gcode_feedrate ; dip into well
G1 $well{$w} Z30 $gcode_feedrate ; raise out of well
; end of get paint
EOT

}

# print common g-code header
sub gcode_header {
    my $fh = shift;

    print $fh <<'EOT';
; start header
G21    ; [mm] mode
G90    ; absolute mode
M82    ; set extruder to absolute mode
G28    ; home
G92 E0 ; set extruder position to zero
G1 X74 Y120 Z10 F4000 ; move to starting position
G4 S30 ; stop for 30 secs.
; end header
EOT

}

# print common g-code footer
sub gcode_footer {
    my $fh = shift;

    print $fh <<'EOT';
; start footer
G1 X74 Y120 Z50 F4000 ; raise brush over paint
; end footer
EOT

}
