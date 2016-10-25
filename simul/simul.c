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
uint8_t		pin_state = 0;		// current port B
uint8_t		ddr_state = 0;		// ddr port B

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

float		leds[14][8] = {
	{VX1(0), VY1(0), VX2(0), VY2(0), VX3(0), VY3(0), VX4(0), VY4(0)},
	{VX1(1), VY1(0), VX2(1), VY2(0), VX3(1), VY3(0), VX4(1), VY4(0)},
	{VX1(1), VY1(1), VX2(1), VY2(1), VX3(1), VY3(1), VX4(1), VY4(1)},
	{VX1(1), VY1(2), VX2(1), VY2(2), VX3(1), VY3(2), VX4(1), VY4(2)},
	{VX1(1), VY1(3), VX2(1), VY2(3), VX3(1), VY3(3), VX4(1), VY4(3)},
	{VX1(3), VY1(0), VX2(3), VY2(0), VX3(3), VY3(0), VX4(3), VY4(0)},
	{VX1(3), VY1(1), VX2(3), VY2(1), VX3(3), VY3(1), VX4(3), VY4(1)},
	{VX1(3), VY1(2), VX2(3), VY2(2), VX3(3), VY3(2), VX4(3), VY4(2)},
	{VX1(4), VY1(0), VX2(4), VY2(0), VX3(4), VY3(0), VX4(4), VY4(0)},
	{VX1(4), VY1(1), VX2(4), VY2(1), VX3(4), VY3(1), VX4(4), VY4(1)},
	{VX1(4), VY1(2), VX2(4), VY2(2), VX3(4), VY3(2), VX4(4), VY4(2)},
	{VX1(4), VY1(3), VX2(4), VY2(3), VX3(4), VY3(3), VX4(4), VY4(3)},
	{VX1(0), VY1(5), VX2(0), VY2(5), VX3(0), VY3(5), VX4(0), VY4(5)},
	{VX1(0), VY1(6), VX2(0), VY2(6), VX3(0), VY3(6), VX4(0), VY4(6)}
};

// charlieplexing map
// xxxxyyyy where x == 1 output, x == 0 input, y == 1 on, y == 0 off
unsigned char cp[] = {0x00, 0x31, 0x51, 0x91, 0xA2, 0x62, 0x32, 0x64, 0xC4, 0x54, 0xA8, 0xC8, 0x98};

/**
 * called when the AVR change any of the pins on port B
 * so lets update our buffer
 */
void pin_changed_hook(struct avr_irq_t *irq, uint32_t value, void *param)
{
	pin_state = (pin_state & ~(1 << irq->irq)) | (value << irq->irq);
	printf("Changed pin\n");
}

void ddr_hook(struct avr_irq_t *irq, uint32_t value, void *param)
{
	ddr_state = (uint8_t)value;
	printf("Changed ddr %2.x\n", ddr_state);
}

void displayCB(void)		/* function called whenever redisplay needed */
{
	unsigned char curstate = (pin_state & 0x0F) | (ddr_state & 0xF0);
	// OpenGL rendering goes here...
	glClear(GL_COLOR_BUFFER_BIT);

	// Set up modelview matrix
	glMatrixMode(GL_MODELVIEW); // Select modelview matrix
	glLoadIdentity(); // Start with an identity matrix

	// float grid = SZ_PIXSIZE;
	// float size = grid * 0.8;
    glBegin(GL_QUADS);
	glColor3f(1, 0, 0);

	for (int di = 1; di < 13; di++) {
		if (cp[di] == curstate) {
			float	*ledv = leds[di - 1];
			glVertex2f(ledv[0], ledv[1]);
			glVertex2f(ledv[2], ledv[3]);
			glVertex2f(ledv[4], ledv[5]);
			glVertex2f(ledv[6], ledv[7]);
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
		case 'r':
			printf("Starting VCD trace\n");
			avr_vcd_start(&vcd_file);
			break;
		case 's':
			printf("Stopping VCD trace\n");
			avr_vcd_stop(&vcd_file);
			break;
	}
}

// gl timer. if the pin have changed states, refresh display
void timerCB(int i)
{
	static uint8_t oldstate = 0xff;
	// restart timer
	glutTimerFunc(1000 / 64, timerCB, 0);

	if (oldstate != pin_state) {
		oldstate = pin_state;
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
	f.frequency = 8000000;
	printf("firmware %s f=%d mmcu=%s\n", fname, (int)f.frequency, f.mmcu);

	avr = avr_make_mcu_by_name(f.mmcu);
	if (!avr) {
		fprintf(stderr, "%s: AVR '%s' not known\n", argv[0], f.mmcu);
		exit(1);
	}
	avr_init(avr);
	avr_load_firmware(avr, &f);

	// initialize our 'peripheral'
	//button_init(avr, &button, "button");
	// "connect" the output irw of the button to the port pin of the AVR
	//avr_connect_irq(
	//	button.irq + IRQ_BUTTON_OUT,
	//	avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('C'), 0));

	avr_irq_register_notify(
		avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), IOPORT_IRQ_DIRECTION_ALL),
		ddr_hook,
		NULL);

	// connect the 4 charlieplexed pins (0 to 3) on port B to our callback
	for (int i = 0; i < 4; i++) {
		avr_irq_register_notify(
			avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), i),
			pin_changed_hook, 
			NULL);
	}

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
	avr_vcd_init(avr, "gtkwave_output.vcd", &vcd_file, 100000 /* usec */);
	avr_vcd_add_signal(&vcd_file, 
		avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), IOPORT_IRQ_PIN_ALL), 8 /* bits */ ,
		"portb" );
	//avr_vcd_add_signal(&vcd_file, 
	//	button.irq + IRQ_BUTTON_OUT, 1 /* bits */ ,
	//	"button" );

	// 'raise' it, it's a "pullup"
	//avr_raise_irq(button.irq + IRQ_BUTTON_OUT, 1);

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
