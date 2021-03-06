/*
THE COMPUTER CODE CONTAINED HEREIN IS THE SOLE PROPERTY OF PARALLAX
SOFTWARE CORPORATION ("PARALLAX").  PARALLAX, IN DISTRIBUTING THE CODE TO
END-USERS, AND SUBJECT TO ALL OF THE TERMS AND CONDITIONS HEREIN, GRANTS A
ROYALTY-FREE, PERPETUAL LICENSE TO SUCH END-USERS FOR USE BY SUCH END-USERS
IN USING, DISPLAYING,  AND CREATING DERIVATIVE WORKS THEREOF, SO LONG AS
SUCH USE, DISPLAY OR CREATION IS FOR NON-COMMERCIAL, ROYALTY OR REVENUE
FREE PURPOSES.  IN NO EVENT SHALL THE END-USER USE THE COMPUTER CODE
CONTAINED HEREIN FOR REVENUE-BEARING PURPOSES.  THE END-USER UNDERSTANDS
AND AGREES TO THE TERMS HEREIN AND ACCEPTS THE SAME BY USE OF THIS FILE.  

COPYRIGHT 1993-1998 PARALLAX SOFTWARE CORPORATION.  ALL RIGHTS RESERVED.
*/
/*
 * $Source: f:/miner/source/2d/rcs/tmapbits.c $
 * $Revision: 1.2 $
 * $Author: john $
 * $Date: 1993/10/15 16:23:38 $
 *
 * A sample bitmap to test functions with.
 *
 * $Log: tmapbits.c $
 * Revision 1.2  1993/10/15  16:23:38  john
 * y
 * 
 * Revision 1.1  1993/09/08  11:44:36  john
 * Initial revision
 * 
 *
 */

#define a 10
#define b 11
#define c 12
#define d 13
#define e 14
#define f 15

unsigned char Test_bitmap_data[64*64] = {
 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
 1,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,1,
 1,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,1,
 1,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,f,f,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,1,1,
 1,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,f,f,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,1,1,1,
 1,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,1,1,1,
 1,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,1,1,1,
 1,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,1,1,1,
 1,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,a,a,a,a,a,a,a,a,a,a,a,a,a,a,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,1,2,0,0,0,0,0,0,0,0,0,0,0,0,3,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,4,1,2,0,0,0,0,0,0,0,0,0,0,3,1,5,a,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,f,f,0,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,4,1,2,0,0,0,0,0,0,0,0,3,1,5,0,a,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,f,f,f,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,4,1,2,0,0,0,0,0,0,3,1,5,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,f,f,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,0,4,1,2,0,0,0,0,3,1,5,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,0,f,f,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,0,0,4,1,2,0,0,3,1,5,0,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,f,f,f,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,0,0,0,4,1,2,3,1,5,0,0,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,f,f,f,0,0,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,0,0,0,0,4,1,1,5,0,0,0,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,f,f,0,0,0,0,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,0,0,0,0,6,1,1,7,0,0,0,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,f,f,0,0,0,0,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,0,0,0,6,1,8,9,1,7,0,0,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,f,f,0,0,0,0,0,1,1,1,
 1,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,0,0,0,6,1,8,0,0,9,1,7,0,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,0,f,f,0,0,0,0,1,1,1,
 1,0,0,0,f,f,f,f,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,a,0,0,0,6,1,8,0,0,0,0,9,1,7,0,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,f,f,0,0,0,1,1,1,
 1,0,0,0,f,f,f,f,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,a,0,0,6,1,8,0,0,0,0,0,0,9,1,7,0,0,a,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,0,f,f,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,0,6,1,8,0,0,0,0,0,0,0,0,9,1,7,0,a,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,a,6,1,8,0,0,0,0,0,0,0,0,0,0,9,1,7,a,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,a,a,a,a,a,a,a,a,a,a,a,a,a,a,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,0,1,1,1,
 1,0,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,0,1,1,1,
 1,0,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,0,1,1,1,
 1,0,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,0,1,1,1,
 1,0,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,0,0,0,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,0,1,1,1,
 1,0,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,1,1,1,
 1,0,6,1,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,f,f,f,f,f,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,1,7,1,1,
 1,6,1,8,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,1,7,1,
 1,1,8,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,1,1,
 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
} ;

