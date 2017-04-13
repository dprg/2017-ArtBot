
//char pixel_page = 0x3d; // 00111101 strokes: 1, space, 4, space, space

//char pixel_page = 0x7d; // 01111101 strokes: 1, space, 4, 1, space

char pixel_page = 0x71;   // 10000101

//char pixel_page = 0xff; // 11111111 strokes: 8, 

char max_stroke_pixels = 4;
char strt_flg = 0;
char stroke_len = 0;


int main (void) {
	int j;
	printf("pixel_page: %b\n",pixel_page);
	for (j=0;j<=7;j++) {                    
		//char test_val = pixel_page>>j ;  // test 1
		char test_val = pixel_page<<j ;    // test 2
		//printf ("test_val: %b\n",test_val);
		//if (test_val & 0x01) {          // test 1
		if (test_val & 0x80) {            // test 2
			stroke_len++;
			if (strt_flg == 0) {
				printf ("stroke_start\n");
				//printf ("test_val: %b\n",test_val);
				strt_flg = 1;
			}
			if (stroke_len == 4){
					printf ("stroke_end\n");
					printf ("test_val: %b\n",test_val);
					printf ("stroke_len: %x\n",stroke_len);
					stroke_len = 0;
					strt_flg = 0;
				}
		}
		else {
			if (strt_flg == 1) {
				printf ("stroke_end\n");
				printf ("test_val: %b\n",test_val);
				printf ("stroke_len: %x\n",stroke_len);
				stroke_len = 0;
				strt_flg = 0;
			}
		}
	}
	// instead of the below, just index to next position
	printf ("stroke_end\n");
	printf ("stroke_len: %x\n",stroke_len);
	strt_flg = 0;
	
	
}