"""
Logging utilities for VPP Multi-Container Chain

Provides centralized logging functionality with both console and file output.
"""

import logging
from datetime import datetime
from pathlib import Path

# Global logger instance
log = None

def setup_logger(name="vpp_chain", level=logging.INFO):
    """Setup and configure logger with both file and console handlers"""
    global log
    
    # Create logs directory if it doesn't exist
    log_dir = Path("/tmp/vpp_logs")
    log_dir.mkdir(exist_ok=True)
    
    # Create logger
    logger = logging.getLogger(name)
    logger.setLevel(level)
    
    # Clear any existing handlers
    logger.handlers.clear()
    
    # Create formatters
    detailed_formatter = logging.Formatter(
        '[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    simple_formatter = logging.Formatter(
        '[%(asctime)s] [%(levelname)s] %(message)s',
        datefmt='%H:%M:%S'
    )
    
    # File handler - detailed logs
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"vpp_chain_{timestamp}.log"
    
    file_handler = logging.FileHandler(log_file)
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(detailed_formatter)
    logger.addHandler(file_handler)
    
    # Console handler - clean output
    console_handler = logging.StreamHandler()
    console_handler.setLevel(level)
    console_handler.setFormatter(simple_formatter)
    logger.addHandler(console_handler)
    
    # Set global logger
    log = logger
    
    logger.info(f"Logger initialized. Log file: {log_file}")
    return logger

def get_logger():
    """Get the global logger instance"""
    global log
    if log is None:
        log = setup_logger()
    return log

# Color codes for console output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    NC = '\033[0m'  # No Color
    
    @staticmethod
    def colorize(text, color):
        """Add color to text for console output"""
        return f"{color}{text}{Colors.NC}"
    
    @staticmethod
    def success(text):
        return Colors.colorize(f"✅ {text}", Colors.GREEN)
    
    @staticmethod
    def error(text):
        return Colors.colorize(f"❌ {text}", Colors.RED)
    
    @staticmethod
    def warning(text):
        return Colors.colorize(f"⚠️ {text}", Colors.YELLOW)
    
    @staticmethod
    def info(text):
        return Colors.colorize(f"ℹ️ {text}", Colors.BLUE)

def log_success(message):
    """Log success message with color"""
    if log:
        log.info(message)
    print(Colors.success(message))

def log_error(message):
    """Log error message with color"""
    if log:
        log.error(message)
    print(Colors.error(message))

def log_warning(message):
    """Log warning message with color"""
    if log:
        log.warning(message)
    print(Colors.warning(message))

def log_info(message):
    """Log info message with color"""
    if log:
        log.info(message)
    print(Colors.info(message))