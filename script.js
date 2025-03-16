const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

let terminalBuffer = "";
let consoleLogBuffer = "";

const WASM = {
    instance: null,

    async initialize() {
        try {
            const response = await fetch("./zig-out/bin/tinylisp.wasm");
            const buffer = await response.arrayBuffer();
            const wasmModule = await WebAssembly.instantiate(buffer, this.importObject);
            this.instance = wasmModule.instance;
            this.instance.exports.tinylisp_init();
        } catch (error) {
            console.error("Failed to initialize WASM:", error);
        }
    },

    getString(ptr, len) {
        const memory = this.instance.exports.memory;
        return textDecoder.decode(new Uint8Array(memory.buffer, ptr, len));
    },

    importObject: {
        env: {
            jsTerminalWriteBuffer: (ptr, len) => {
                terminalBuffer += WASM.getString(ptr, len);
            },
            jsConsoleLogWrite: (ptr, len) => {
                consoleLogBuffer += WASM.getString(ptr, len);
            },
            jsConsoleLogFlush: () => {
                console.log(consoleLogBuffer);
                consoleLogBuffer = "";
            },
        },
    },
};

class Terminal {
    constructor() {
        this.output = document.getElementById('output');
        this.input = document.getElementById('input');
        this.prompt = document.getElementById('prompt');
        this.commandHistory = [];
        this.historyIndex = -1;

        this.initializeInputListener();
    }

    initializeInputListener() {
        this.input.addEventListener('keydown', (e) => this.handleInput(e));
    }

    handleInput(event) {
        if (event.key === 'Enter') {
            this.processCommand(this.input.value.trim());
            this.input.value = '';
        } else if (event.key === 'ArrowUp') {
            this.navigateHistory(-1);
        } else if (event.key === 'ArrowDown') {
            this.navigateHistory(1);
        }
    }

    processCommand(input) {
        if (!input || input.trim() === "") return;

        this.commandHistory.push(input);
        this.historyIndex = this.commandHistory.length;

        // Display the command in green
        this.appendOutput(`> ${input}`, 'output-command');

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

    executeWasmCommand(input) {
        const nullTerminatedInput = input + "\0";
        const encodedInput = textEncoder.encode(nullTerminatedInput);
        const inputAddress = WASM.instance.exports._wasm_alloc(encodedInput.length);
        const inputArray = new Uint8Array(WASM.instance.exports.memory.buffer, inputAddress);
        inputArray.set(encodedInput);

        WASM.instance.exports.tinylisp_run(inputAddress, encodedInput.length);
        this.appendOutput(terminalBuffer, 'output-result');
        terminalBuffer = "";

        // Free allocated memory
        WASM.instance.exports._wasm_free(inputAddress);
    }

    appendOutput(text, className = 'output-result') {
        const outputLine = document.createElement('div');
        outputLine.textContent = text;
        outputLine.className = className; // Apply the specified class
        this.output.appendChild(outputLine);

        // Ensure the terminal scrolls to the bottom after appending new content
        this.scrollToBottom();
    }

    clearTerminal() {
        // Clear the terminal output but preserve the banner
        this.output.innerHTML = '<div id="banner">Welcome to <a href="https://github.com/daneelsan/tinylisp/blob/main/README.md" target="_blank">TINYLISP</a>!</div>';
    }

    navigateHistory(direction) {
        if (direction === -1 && this.historyIndex > 0) {
            this.historyIndex--;
        } else if (direction === 1 && this.historyIndex < this.commandHistory.length - 1) {
            this.historyIndex++;
        } else if (direction === 1) {
            this.historyIndex = this.commandHistory.length;
        }

        this.input.value = this.commandHistory[this.historyIndex] || '';
    }

    scrollToBottom() {
        setTimeout(() => {
            this.output.scrollTop = this.output.scrollHeight;
        }, 0);
    }
}

async function bootstrap() {
    await WASM.initialize();
    new Terminal();
}

bootstrap();