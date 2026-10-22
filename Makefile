CC = gcc
CFLAGS = -municode -mwindows
TARGET = winbrightsync.exe
OBJS = winbrightsync.o

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $^ -o $(TARGET)

clean:
	rm -f $(TARGET) $(OBJS)
	