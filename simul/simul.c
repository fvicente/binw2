/*
 *	simul.c
 *
 *	Copyright 2016, Fernando Vicente <fvicente@gmail.com>
 *
 *	bin2w simulator.
 */

#include <stdlib.h>
#include <stdio.h>
#include <libgen.h>
#if __APPLE__
#include <GLUT/glut.h>
#else
#include <GL/glut.h>
#endif
#include <pthread.h>

#include "sim_avr.h"
#include "avr_ioport.h"
#include "sim_elf.h"
#include "sim_gdb.h"
#include "sim_vcd_file.h"

#include "button.h"

button_t	button;
int			do_button_press = 0;
avr_t		*avr = NULL;
avr_vcd_t	vcd_file;
int			display_flag = 0;
uint8_t		pin_state = 0;		// current port B
uint8_t		ddr_state = 0;		// ddr port B

static uint8_t		last_cp_state = 0;		// last charlieplexing state

#define		SZ_PIXSIZE		32.0

const float	SZ_GRID = SZ_PIXSIZE;
const float	SZ_LED = SZ_PIXSIZE * 0.8;
int			window;

/**
 * 6 |  14 <- AM
 * 5 |  13 <- PM
 * 4 |
 * 3 |    5     12
 * 2 |    4   8 11
 * 1 |    3   7 10
 * 0 |  1 2   6 9
 * --+------------
 *      0 1 2 3 4
 *
 *      H H : M M
 */

#define		VX1(x)		((x * SZ_GRID) + SZ_LED)
#define		VY1(y)		((y * SZ_GRID) + SZ_LED)
#define		VX2(x)		(x * SZ_GRID)
#define		VY2(y)		((y * SZ_GRID) + SZ_LED)
#define		VX3(x)		(x * SZ_GRID)
#define		VY3(y)		(y * SZ_GRID)
#define		VX4(x)		((x * SZ_GRID) + SZ_LED)
#define		VY4(y)		(y * SZ_GRID)

#define		VERTEX(x, y) VX1(x), VY1(y), VX2(x), VY2(y), VX3(x), VY3(y), VX4(x), VY4(y)

float		leds[14][8] = {
	{VERTEX(0, 0)},
	{VERTEX(1, 0)},
	{VERTEX(1, 1)},
	{VERTEX(1, 2)},
	{VERTEX(1, 3)},
	{VERTEX(3, 0)},
	{VERTEX(3, 1)},
	{VERTEX(3, 2)},
	{VERTEX(4, 0)},
	{VERTEX(4, 1)},
	{VERTEX(4, 2)},
	{VERTEX(4, 3)},
	{VERTEX(0, 5)},
	{VERTEX(0, 6)}
};

// charlieplexing map
// xxxxyyyy where x == 1 output, x == 0 input, y == 1 on, y == 0 off
unsigned char cp[] = {0x00, 0x31, 0x51, 0x91, 0xA2, 0x62, 0x32, 0x64, 0xC4, 0x54, 0xA8, 0xC8, 0x98};
// delays to keep the leds on for a while, to simulate persistence of vision
#define		POV		1
int delays[] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

static void set_pov(int cp_state)
{
	for (int di = 1; di <= 12; di++) {
		if (cp[di] == cp_state) {
			delays[di] = POV;
		}
	}
}
/**
 * called when the AVR change any of the pins on port B
 * so lets update our buffer
 */
void pin_changed_hook(struct avr_irq_t *irq, uint32_t value, void *param)
{
	uint8_t	cp_state;

	//printf("irq: %d - value: 0x%.2X - irq->value: 0x%.2X - param: %s - ddr_state: %.2X\n", irq->irq, value, irq->value, (char *)param, ddr_state);
	//pin_state = (pin_state & ~(1 << irq->irq)) | (value << irq->irq);
	// note: filter only pins configured as input by and'íng ddr_state
	pin_state = (uint8_t)value;

	cp_state = ((pin_state & ddr_state) & 0x0F) | ((ddr_state << 4) & 0xF0);
	//pin_state = (value << irq->irq);
	//pin_state = (uint8_t)(value & 0xFF);
	//printf("Changed pin 0x%.2X\n", pin_state);
	//	glutPostRedisplay();
	if (last_cp_state != cp_state) {
		// printf("1>cp_state 0x%.2X\n", cp_state);
		last_cp_state = cp_state;
		set_pov(cp_state);
		display_flag++;
	}
}

void ddr_hook(struct avr_irq_t *irq, uint32_t value, void *param)
{
	uint8_t	cp_state;
//	ddr_state = (ddr_state & ~(1 << irq->irq)) | (value << irq->irq);

	ddr_state = (uint8_t)value;
	cp_state = ((pin_state & ddr_state) & 0x0F) | ((ddr_state << 4) & 0xF0);
	//printf("Changed ddr 0x%.2X - 0x%.2X & 0x0F - %s - irq: %d - flags: %d - value: %d -- value: %d\n", ddr_state, ddr_state & 0x0F, irq->name, irq->irq, irq->flags, irq->value, value);
	//	glutPostRedisplay();
	//display_flag++;
	if (last_cp_state != cp_state) {
		// printf("2>cp_state 0x%.2X\n", cp_state);
		last_cp_state = cp_state;
		set_pov(cp_state);
		display_flag++;
	}
}

void displayCB(void)		/* function called whenever redisplay needed */
{
	float			*ledv;
	static unsigned char laststate = 0xFF;
	//unsigned char	curstate = (pin_state & 0x0F) | ((ddr_state << 4) & 0xF0);
	//	printf("curstate 0x%.2X\n", curstate);
	//if (curstate == laststate) {
	//	return;
	//}
	// OpenGL rendering goes here...
	glClear(GL_COLOR_BUFFER_BIT);

	// Set up modelview matrix
	glMatrixMode(GL_MODELVIEW); // Select modelview matrix
	glLoadIdentity(); // Start with an identity matrix

    glBegin(GL_QUADS);
	glColor3f(1, 0, 0);

	//if (curstate != laststate) {
	//	laststate = curstate;
	//	printf("**curstate 0x%.2X\n", curstate);
	//}
	for (int di = 1; di <= 12; di++) {
		if (delays[di] > 0) {
			ledv = leds[di - 1];
			glVertex2f(ledv[0], ledv[1]);
			glVertex2f(ledv[2], ledv[3]);
			glVertex2f(ledv[4], ledv[5]);
			glVertex2f(ledv[6], ledv[7]);
			delays[di]--;
		}
	}

	glEnd();
	glutSwapBuffers();
	//glFlush();				/* Complete any pending operations */
}

void keyCB(unsigned char key, int x, int y)	/* called on key press */
{
	if (key == 'q') {
		exit(0);
	}
	//static uint8_t buf[64];
	switch (key) {
		case 'q':
		case 0x1f: // escape
			exit(0);
			break;
		case ' ':
			do_button_press++; // pass the message to the AVR thread
			break;
		// case 'r':
		// 	printf("Starting VCD trace\n");
		// 	avr_vcd_start(&vcd_file);
		// 	break;
		// case 's':
		// 	printf("Stopping VCD trace\n");
		// 	avr_vcd_stop(&vcd_file);
		// 	break;
	}
}

// gl timer. if the pin have changed states, refresh display
void timerCB(int i)
{
	static int old_display_flag = 0;
	// restart timer
	glutTimerFunc(1000 / 64, timerCB, 0);

	if (old_display_flag != display_flag) {
		glutPostRedisplay();
	}
}

static void *avr_run_thread(void * oaram)
{
	int b_press = do_button_press;
	
	while (1) {
		avr_run(avr);
		if (do_button_press != b_press) {
			b_press = do_button_press;
			printf("Button pressed\n");
			button_press(&button, 1000000);
		}
	}
	return NULL;
}

int main(int argc, char *argv[])
{
	elf_firmware_t		f;
	const char			*fname="../src/binw2.elf";
	const char			*mmcu="attiny13";

	elf_read_firmware(fname, &f);

	snprintf(f.mmcu, sizeof(f.mmcu) - 1, "%s", mmcu);
	f.frequency = 4800000;
	printf("firmware %s f=%d mmcu=%s\n", fname, (int)f.frequency, f.mmcu);

	avr = avr_make_mcu_by_name(f.mmcu);
	if (!avr) {
		fprintf(stderr, "%s: AVR '%s' not known\n", argv[0], f.mmcu);
		exit(1);
	}
	avr_init(avr);
	avr_load_firmware(avr, &f);

	// initialize our 'peripheral'
	button_init(avr, &button, "button");
	// "connect" the output irw of the button to the port pin of the AVR
	avr_connect_irq(
		button.irq + IRQ_BUTTON_OUT,
		avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), IOPORT_IRQ_PIN4));

	avr_irq_register_notify(
		avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), IOPORT_IRQ_DIRECTION_ALL),
		ddr_hook,
		NULL);

	// connect the 4 charlieplexed pins (0 to 3) on port B to our callback
	//for (int i = 0; i < 4; i++) {
		avr_irq_register_notify(
			avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), IOPORT_IRQ_PIN_ALL),
			pin_changed_hook, 
			"portb");
	//}

	// even if not setup at startup, activate gdb if crashing
	avr->gdb_port = 1234;
	if (0) {
		//avr->state = cpu_Stopped;
		avr_gdb_init(avr);
	}

	/*
	 *	VCD file initialization
	 *	
	 *	This will allow you to create a "wave" file and display it in gtkwave
	 *	Pressing "r" and "s" during the demo will start and stop recording
	 *	the pin changes
	 */
	// avr_vcd_init(avr, "gtkwave_output.vcd", &vcd_file, 100000 /* usec */);
	// avr_vcd_add_signal(&vcd_file, 
	// 	avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), IOPORT_IRQ_PIN_ALL), 8 /* bits */ ,
	// 	"portb" );
	// avr_vcd_add_signal(&vcd_file, 
	// 	button.irq + IRQ_BUTTON_OUT, 1 /* bits */ ,
	// 	"button" );

	// 'raise' it, it's a "pullup"
	avr_raise_irq(button.irq + IRQ_BUTTON_OUT, 0);

	printf( "Demo launching: 'LED' bar is PORTB, updated every 1/64s by the AVR\n"
			"   firmware using a timer. If you press 'space' this presses a virtual\n"
			"   'button' that is hooked to the virtual PORTC pin 0 and will\n"
			"   trigger a 'pin change interrupt' in the AVR core, and will 'invert'\n"
			"   the display.\n"
			"   Press 'q' to quit\n\n"
			"   Press 'r' to start recording a 'wave' file\n"
			"   Press 's' to stop recording\n"
			);

	/*
	 * OpenGL init, can be ignored
	 */
	glutInit(&argc, argv);		/* initialize GLUT system */

	glutInitDisplayMode(GLUT_RGB | GLUT_DOUBLE);
	glutInitWindowSize(5 * SZ_PIXSIZE, 7 * SZ_PIXSIZE);
	window = glutCreateWindow("Glut");	/* create window */

	// Set up projection matrix
	glMatrixMode(GL_PROJECTION); // Select projection matrix
	glLoadIdentity(); // Start with an identity matrix
	glOrtho(0, 5 * SZ_PIXSIZE, 0, 7 * SZ_PIXSIZE, 0, 10);
	//glScalef(1, -1, 1);
	//glTranslatef(0, -7 * SZ_PIXSIZE, 0);

	glutDisplayFunc(displayCB);		/* set window's display callback */
	glutKeyboardFunc(keyCB);		/* set window's key callback */
	glutTimerFunc(1000 / 24, timerCB, 0);

	// the AVR run on it's own thread. it even allows for debugging!
	pthread_t run;
	pthread_create(&run, NULL, avr_run_thread, NULL);

	glutMainLoop();
}
