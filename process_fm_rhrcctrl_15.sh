#!/usr/bin/env bash

# IMPORTANT: For the correct data to be acquired, you must change the rhrcctrl CV to 15 before scanning.

# Requires afni (dicom_hinfo), dcm2nii, and FSL to be installed on your machine.

# Call from inside a directory containing your field map dicoms (and only your field map dicoms). Dicoms should have *.dcm extension
# Hard coded to expect 4 echos, real/imag data for each
# Reads the echo spacing from the dicom headers 

# You do not want the shim to change between the field map acquisition and the EPI scan you are planning to apply it to. 
# Ideally you also don't want the centre frequency to change (I think), but I don't know how to skip that without also skipping the gain prescans.

# I'm not doing any fitting of the echos - I'm just calculating the phase difference between echos.

# Outputs TE1_mag (to use as the magnitude image) and 3 phase difference images calculated from different echos (fm_e2_e3,fm_e3_e4, and fm_e2_e4). 
# Phase difference images created from echo 1 look weird and I'm not sure why. I've commented out their generation to avoid confusion.
# Also saves a bunch of intermediate images.

# Some useful info:
# http://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FUGUE/Guide
# https://www.jiscmail.ac.uk/cgi-bin/webadmin?A2=ind1208&L=FSL&P=R71288&1=FSL&9=A&J=on&d=No+Match%3BMatch%3BMatches&z=4
# https://www.jiscmail.ac.uk/cgi-bin/webadmin?A2=ind1212&L=FSL&P=R48486&1=FSL&9=A&I=-3&J=on&d=No+Match%3BMatch%3BMatches&z=4

# Erin Mazerolle (erinmaz@gmail.com), updated Nov 20, 2018

mkdir mag
mkdir phase
mkdir real
mkdir imag

mkdir sort
ls | xargs -n 100 dicom_hinfo -tag 0020,0013 >> sort/_instancenumb
sort -n -k 2 sort/_instancenumb > sort/_instancenumb_sort

# Get the echo spacing.
file1=`more sort/_instancenumb_sort | head -1 | awk '{print $1}'`
#skip four files to get the next echo time
file2=`more sort/_instancenumb_sort | head -5 | tail -1 | awk '{print $1}'`
TE1=`dicom_hinfo -tag 0018,0081 $file1 | awk '{print $2}'`
TE2=`dicom_hinfo -tag 0018,0081 $file2 | awk '{print $2}'`
echo_spacing=`echo $TE2 - $TE1 | bc`
i=1
while read line
do
  word=(${line})
  if [ $i -eq 1 ]; then
  	mv $word mag/.
  	let i=$i+1
  elif [ $i -eq 2 ]; then
  	mv $word phase/.
  	let i=$i+1
  elif [ $i -eq 3 ]; then
  	mv $word imag/.
  	let i=$i+1
  elif [ $i -eq 4 ]; then
  	mv $word real/.
  	i=1
  fi
done < sort/_instancenumb_sort

dcm2niix imag
dcm2niix real
dcm2niix mag
dcm2niix phase

fslmerge -t imag.nii.gz `ls imag/*.nii.gz`
fslmerge -t real.nii.gz `ls real/*.nii.gz`


# Create a mask to modulate alternating slices to deal with RF chopping 
# I don't actually know what RF chopping is, but Ethan noticed my images one day and suggested I do this. Thanks Ethan!
fslmaths real.nii.gz -bin -dilall mask
fslmaths mask -sub 1 mask_zero
fileinfo=`fslinfo mask`
nslices=`echo $fileinfo | awk '{print $8}'`
for slice in `seq 1 2 $nslices`
do
  let slice2=$slice-1
  fslmaths mask -roi 0 -1 0 -1 $slice2 1 0 -1 -bin mask_${slice}
  fslmaths mask_zero -add mask_${slice} mask_zero
  rm mask_${slice}.nii*
done

rm mask.nii*
fslmaths mask_zero -mul -2 mask_alt_slices
fslmaths mask_alt_slices -add 1 mask_alt_slices
rm mask_zero.nii*

fslmaths real.nii.gz -mul mask_alt_slices real_mod
fslmaths imag.nii.gz -mul mask_alt_slices imag_mod

fslsplit real_mod real -t
fslsplit imag_mod imag -t

fslcomplex -complex real0000 imag0000 TE1_complex
fslcomplex -realabs TE1_complex TE1_mag
fslcomplex -complex real0003 imag0003 TE4_complex
fslcomplex -complex real0002 imag0002 TE3_complex
fslcomplex -complex real0001 imag0001 TE2_complex

fslcomplex -realphase TE1_complex phase0_rad
fslcomplex -realphase TE2_complex phase1_rad
fslcomplex -realphase TE3_complex phase2_rad
fslcomplex -realphase TE4_complex phase3_rad

prelude -a TE1_mag -p phase0_rad -o phase0_unwrapped_rad
prelude -a TE1_mag -p phase1_rad -o phase1_unwrapped_rad
prelude -a TE1_mag -p phase2_rad -o phase2_unwrapped_rad
prelude -a TE1_mag -p phase3_rad -o phase3_unwrapped_rad

#field maps created with echo 1 look wrong. not sure why.
#fslmaths phase1_unwrapped_rad -sub phase0_unwrapped_rad -mul 1000 -div 2.064 fm_e1_e2 -odt float
fslmaths phase2_unwrapped_rad -sub phase1_unwrapped_rad -mul 1000 -div ${echo_spacing} fm_e2_e3 -odt float
#fslmaths phase3_unwrapped_rad -sub phase2_unwrapped_rad -mul 1000 -div ${echo_spacing}  fm_e3_e4 -odt float
#fslmaths phase2_unwrapped_rad -sub phase0_unwrapped_rad -mul 1000 -div 4.128 fm_e1_e3 -odt float
#fslmaths phase3_unwrapped_rad -sub phase0_unwrapped_rad -mul 1000 -div 6.192 fm_e1_e4 -odt float
#fslmaths phase3_unwrapped_rad -sub phase1_unwrapped_rad -mul 1000 -div ${echo_spacing}  -div 2 fm_e2_e4 -odt float
#could average the three good field maps together if you wanted.

# bug in FUGUE and/or fslcomplex means orientation info gets lost, so we must add it back in
fslcpgeom real0001 fm_e2_e3
#fslcpgeom real0001 fm_e2_e4
#fslcpgeom real0001 fm_e3_e4
fslcpgeom real0001 TE1_mag

