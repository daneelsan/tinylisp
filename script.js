// TextEncoder and TextDecoder for handling string encoding/decoding
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

// Buffers for storing terminal output and console logs
let terminalBuffer = "";
let consoleLogBuffer = "";

// WASM module interface
const WASM = {
    instance: null, // Holds the WebAssembly instance

    async initialize() {
        try {
            // Fetch the WASM binary
            const response = await fetch("./zig-out/bin/tinylisp.wasm");
            const buffer = await response.arrayBuffer();
            // Instantiate the WASM module
            const wasmModule = await WebAssembly.instantiate(buffer, this.importObject);
            this.instance = wasmModule.instance;
            // Initialize the Lisp interpreter
            this.instance.exports.tinylisp_init();
        } catch (error) {
            console.error("Failed to initialize WASM:", error);
        }
    },

    // Get a string from WASM memory
    getString(ptr, len) {
        const memory = this.instance.exports.memory;
        return textDecoder.decode(new Uint8Array(memory.buffer, ptr, len));
    },

    // Import object for WASM, providing JavaScript functions to the module
    importObject: {
        env: {
            // Write to the terminal buffer
            jsTerminalWriteBuffer: (ptr, len) => {
                terminalBuffer += WASM.getString(ptr, len);
            },
            // Write to the console log buffer
            jsConsoleLogWrite: (ptr, len) => {
                consoleLogBuffer += WASM.getString(ptr, len);
            },
            // Flush the console log buffer to the browser console
            jsConsoleLogFlush: () => {
                console.log(consoleLogBuffer);
                consoleLogBuffer = "";
            },
        },
    },
};

// Terminal emulator class
class Terminal {
    constructor() {
        // DOM elements
        this.output = document.getElementById('output');
        this.input = document.getElementById('input');
        this.prompt = document.getElementById('prompt');

        // Command history and index
        this.commandHistory = [];
        this.historyIndex = -1;

        // Initialize event listeners
        this.initializeInputListener();
        this.initializeAutoResize();
    }

    // Set up the input event listener
    initializeInputListener() {
        this.input.addEventListener('keydown', (e) => this.handleInput(e));
    }

    // Set up auto-resize for the input textarea
    initializeAutoResize() {
        this.input.addEventListener('input', () => this.autoResizeTextarea());
    }

    // Adjust the height of the input textarea based on its content
    autoResizeTextarea() {
        // Reset the height to auto to recalculate the height
        this.input.style.height = 'auto';
        // Set the height to the scrollHeight (content height)
        this.input.style.height = `${this.input.scrollHeight}px`;
    }

    // Handle keyboard input
    handleInput(event) {
        if (event.key === 'Enter') {
            // Check if Shift is pressed
            if (!event.shiftKey) {
                // Enter (no shift): Add a new line inside the textarea
                const cursorPosition = this.input.selectionStart;
                const value = this.input.value;
                this.input.value = value.slice(0, cursorPosition) + '\n' + value.slice(cursorPosition);
                this.input.setSelectionRange(cursorPosition + 1, cursorPosition + 1); // Move cursor to the new line
                this.autoResizeTextarea(); // Resize the textarea
                event.preventDefault();
            } else {
                // Shift + Enter: Execute the command
                this.processCommand(this.input.value.trim());
                this.input.value = ''; // Clear the input field
                this.autoResizeTextarea(); // Reset the textarea height
                event.preventDefault(); // Prevent default behavior (e.g., form submission)
            }
        } else if (event.key === 'Tab') {
            // Tab: Insert a tab character at the cursor position
            const cursorPosition = this.input.selectionStart;
            const value = this.input.value;
            this.input.value = value.slice(0, cursorPosition) + '\t' + value.slice(cursorPosition);
            this.input.setSelectionRange(cursorPosition + 1, cursorPosition + 1); // Move cursor after the tab
            event.preventDefault(); // Prevent the browser's default behavior
        } else if (event.key === 'ArrowUp') {
            // Navigate command history (up)
            this.navigateHistory(-1);
        } else if (event.key === 'ArrowDown') {
            // Navigate command history (down)
            this.navigateHistory(1);
        } else if (event.ctrlKey && event.key === 'c') {
            // Clear the line input
            this.input.value = '';
        }
    }

    // Process a command entered by the user
    processCommand(input) {
        if (!input || input.trim() === "") return;

        // Add the command to history
        this.commandHistory.push(input);
        this.historyIndex = this.commandHistory.length;

        // Display the command in green
        this.appendOutput(`λ ${input}`, 'output-command');

        // Handle meta commands
        if (input === '?help') {
            window.open("https://github.com/daneelsan/tinylisp/blob/main/README.md", "_blank");
            this.appendOutput("", 'output-result');
        } else if (input === '?clear') {
            this.clearTerminal();
        } else if (input === '?commands') {
            this.appendOutput("Available meta commands:", 'output-result');
            this.appendOutput("?help - Open the documentation", 'output-result');
            this.appendOutput("?clear - Clear the terminal output", 'output-result');
            this.appendOutput("?commands - List available meta commands", 'output-result');
            this.appendOutput("", 'output-result');
        } else {
            this.executeWasmCommand(input);
        }

        this.scrollToBottom();
    }

    // Execute a command in the WASM module
    executeWasmCommand(input) {
        // Null-terminate the input and encode it
        const nullTerminatedInput = input + "\0";
        const encodedInput = textEncoder.encode(nullTerminatedInput);

        // Allocate memory in the WASM module for the input
        const inputAddress = WASM.instance.exports._wasm_alloc(encodedInput.length);
        const inputArray = new Uint8Array(WASM.instance.exports.memory.buffer, inputAddress);
        inputArray.set(encodedInput);

        // Run the command in the WASM module
        WASM.instance.exports.tinylisp_run(inputAddress, encodedInput.length);
        // Append the output to the terminal
        // TODO: Could change the color of the output to red it was ERR
        this.appendOutput(terminalBuffer, 'output-result');
        terminalBuffer = "";

        // Free allocated memory
        WASM.instance.exports._wasm_free(inputAddress);
    }

    // Append output to the terminal
    appendOutput(text, className = 'output-result') {
        const outputLine = document.createElement('div');
        // Replace tabs with 4 spaces
        // TODO: Make these spaces configurable
        outputLine.textContent = text.replace(/\t/g, '    ');
        outputLine.className = className; // Apply the specified class
        this.output.appendChild(outputLine);

        // Ensure the terminal scrolls to the bottom after appending new content
        this.scrollToBottom();
    }

    // Clear the terminal output (but preserve the banner)
    clearTerminal() {
        // Clear the terminal output but preserve the banner
        this.output.innerHTML = '<div id="banner">Welcome to <a href="https://github.com/daneelsan/tinylisp/blob/main/README.md" target="_blank">TINYLISP</a>!</div>';
    }

    // Navigate through command history
    navigateHistory(direction) {
        if (direction === -1 && this.historyIndex > 0) {
            // Move up in history
            this.historyIndex--;
        } else if (direction === 1 && this.historyIndex < this.commandHistory.length - 1) {
            // Move down in history
            this.historyIndex++;
        } else if (direction === 1) {
            // Reset to the end of history
            this.historyIndex = this.commandHistory.length;
        }

        // Update the input field with the selected command
        this.input.value = this.commandHistory[this.historyIndex] || '';
    }

    // Scroll the terminal to the bottom
    scrollToBottom() {
        setTimeout(() => {
            this.output.scrollTop = this.output.scrollHeight;
        }, 0);
    }
}

// Bootstrap function to initialize the WASM module and terminal
async function bootstrap() {
    await WASM.initialize();
    new Terminal();
}

// Start the application
bootstrap();