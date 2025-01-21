#!/bin/bash

# Required package: ncurses-bin
if ! command -v tput &> /dev/null; then
    echo "Installing ncurses..."
    if command -v apt-get &> /dev/null; then
        apt-get update &&  apt-get install -y ncurses-bin
    elif command -v yum &> /dev/null; then
        yum install -y ncurses
    else
        echo "Error: Could not install ncurses. Please install it manually."
        exit 1
    fi
fi

# Terminal setup and cleanup functions
setup_terminal() {
    # Save current screen
    tput smcup
    # Hide cursor
    tput civis
    # Clear screen
    clear
}

cleanup() {
    # Show cursor
    tput cnorm
    # Restore screen
    tput rmcup
    # Clear screen
    clear
}

# Make sure we cleanup on exit
trap cleanup EXIT INT TERM

# Colors and styles
NORMAL=$(tput sgr0)
BOLD=$(tput bold)
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

# Function to get terminal dimensions
get_terminal_size() {
    LINES=$(tput lines)
    COLS=$(tput cols)
}

# Function to draw a box
draw_box() {
    local top=$1
    local left=$2
    local width=$3
    local height=$4
    local title="$5"
    
    # Draw top border with title
    tput cup $top $left
    printf "╔═"
    [ -n "$title" ] && printf " %s " "$title"
    local remaining=$((width - ${#title} - 5))
    printf "%${remaining}s╗" "" | tr " " "═"
    
    # Draw sides
    for ((i=1; i<height-1; i++)); do
        tput cup $((top+i)) $left
        printf "║"
        printf "%${width}s║" ""
    done
    
    # Draw bottom border
    tput cup $((top+height-1)) $left
    printf "╚"
    printf "%${width}s╝" "" | tr " " "═"
}

# Function to display menu items
display_menu_items() {
    local top=$1
    local left=$2
    local selected=$3
    local items=("${@:4}")
    
    for i in "${!items[@]}"; do
        tput cup $((top+i)) $((left+2))
        if [ $i -eq $selected ]; then
            printf "${BOLD}${BLUE}▶ ${WHITE}%s${NORMAL}" "${items[$i]}"
        else
            printf "  %s" "${items[$i]}"
        fi
    done
}

# Function to display scrollable content
display_content() {
    local content="$1"
    local title="$2"
    local scroll_position=${3:-0}
    
    get_terminal_size
    local box_height=$((LINES-4))
    local box_width=$((COLS-4))
    
    # Clear screen and draw box
    clear
    draw_box 1 1 $box_width $box_height "$title"
    
    # Display content with scrolling
    local line_num=0
    while IFS= read -r line; do
        if [ $line_num -ge $scroll_position ] && [ $line_num -lt $((scroll_position + box_height - 2)) ]; then
            tput cup $((2 + line_num - scroll_position)) 3
            printf "%-$((box_width-4))s" "$line"
        fi
        ((line_num++))
    done <<< "$content"
    
    # Draw scrollbar if needed
    if [ $line_num -gt $((box_height-2)) ]; then
        local scroll_ratio=$(( (scroll_position * (box_height-2)) / line_num ))
        tput cup $((2 + scroll_ratio)) $((box_width-1))
        printf "█"
    fi
    
    # Draw footer
    tput cup $((LINES-2)) 2
    printf "Use ↑/↓ to scroll, q to return"
}

# Function to get pod information
get_pod_info() {
    local content
    content=$(printf "%s\n" \
        "📦 Basic Pod Information" \
        "──────────────────────" \
        "Pod ID:      ${RUNPOD_POD_ID:-Not Available}" \
        "RAM:         ${RUNPOD_MEM_GB:-Not Available} GB" \
        "Public IP:   ${RUNPOD_PUBLIC_IP:-Not Available}" \
        "Datacenter:  ${RUNPOD_DC_ID:-Not Available}" \
        "" \
        "💻 Compute Resources" \
        "──────────────────────" \
        "CPU Cores:   ${RUNPOD_CPU_COUNT:-Not Available}" \
        "GPU Count:   ${RUNPOD_GPU_COUNT:-0}" \
        "")

    if [ "${RUNPOD_GPU_COUNT:-0}" != "0" ]; then
        local gpu_info
        gpu_info=$(printf "%s\n" \
            "🎮 GPU Information" \
            "──────────────────────")
        
        if command -v nvidia-smi &> /dev/null; then
            local cuda_version
            cuda_version=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
            gpu_info+=$(printf "\nMax CUDA Version: %s" "${cuda_version}")
        fi
        
        if command -v nvcc &> /dev/null; then
            local nvcc_version
            nvcc_version=$(nvcc --version | grep "release" | awk '{print $5}')
            # Remove trailing comma if present
            nvcc_version=${nvcc_version%,}
            gpu_info+=$(printf "\nPod CUDA Version: %s" "${nvcc_version}")
        fi
        
        content+="${gpu_info}"
    fi
    
    local scroll_position=0
    while true; do
        display_content "$content" "Pod Information" $scroll_position
        read -s -n 1 key
        case $key in
            "A") # Up arrow
                [ $scroll_position -gt 0 ] && ((scroll_position--))
                ;;
            "B") # Down arrow
                ((scroll_position++))
                ;;
            "q") return ;;
        esac
    done
}

# Function to display SSH connection info
display_connection_info() {
    local content
    content=$(printf "%s\n" \
        "🔐 SSH Connection Details" \
        "──────────────────────" \
        "Host:     ${RUNPOD_PUBLIC_IP}" \
        "Port:     ${RUNPOD_TCP_PORT_22}" \
        "Username: root")
    
    if [ -f "/workspace/root_password.txt" ]; then
        local password
        password=$(cat /workspace/root_password.txt)
        content+=$(printf "\nPassword: %s" "${password}")
    fi
    
    content+=$(printf "\n\nSSH Command:\nssh root@%s -p %s" \
        "${RUNPOD_PUBLIC_IP}" "${RUNPOD_TCP_PORT_22}")
    
    local scroll_position=0
    while true; do
        display_content "$content" "SSH Connection Details" $scroll_position
        read -s -n 1 key
        case $key in
            "A") # Up arrow
                [ $scroll_position -gt 0 ] && ((scroll_position--))
                ;;
            "B") # Down arrow
                ((scroll_position++))
                ;;
            "q") return ;;
        esac
    done
}

# Function to setup SSH
setup_ssh() {
    clear
    echo -e "${BLUE}Setting up SSH access...${NORMAL}"
    
    # Generate random password
    local password
    password=$(openssl rand -base64 12)
    echo "$password" > /workspace/root_password.txt
    echo "root:${password}" | chpasswd
    
    # Configure SSH
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    # Start SSH service
    service ssh start >/dev/null 2>&1
    
    echo -e "${GREEN}SSH setup completed successfully!${NORMAL}"
    sleep 1
    
    # Show connection details
    display_connection_info
}

# Function to draw fancy header
draw_header() {
    local title="$1"
    local width=$2
    local top=$3
    local left=$4
    
    # Calculate padding for centering
    local title_len=${#title}
    local padding=$(( (width - title_len - 2) / 2 ))
    
    # Draw top decorative line
    tput cup $top $left
    printf "╭%s┤ %s ├%s╮" "$(printf '─%.0s' $(seq 1 $padding))" "$title" "$(printf '─%.0s' $(seq 1 $padding))"
    
    # Return bottom position
    echo $((top + 1))
}

# Function to draw fancy footer
draw_footer() {
    local text="$1"
    local width=$2
    local top=$3
    local left=$4
    
    # Draw bottom decorative line
    tput cup $top $left
    printf "╰%s╯" "$(printf '─%.0s' $(seq 1 $((width-2))))"
    
    # Draw navigation help
    tput cup $((top+1)) $left
    printf "%s" "$text"
}

# Enhanced menu item display
draw_menu_item() {
    local text="$1"
    local selected=$2
    local width=$3
    local icon="${text:0:2}"
    local label="${text:3}"
    
    if [ "$selected" = true ]; then
        printf "${BOLD}${BLUE}▶ ${icon} ${WHITE}%-$((width-5))s${NORMAL}" "$label"
    else
        printf "  ${icon} %-$((width-5))s" "$label"
    fi
}

# Function to handle zero GPU case
handle_zero_gpu() {
    echo "Setting up simple HTTP server for zero GPU mode..."
    
    # Kill any running jupyter-lab processes
    pkill jupyter-lab || true
    
    # Kill any existing HTTP server on port 8888
    pkill -f "python3 -m http.server 8888" || true
    
    # Start simple HTTP server in /workspace in background with all output redirected
    cd /workspace
    nohup python3 -m http.server 8888 > /dev/null 2>&1 &
    cd - > /dev/null
}

# Main menu function
show_menu() {
    setup_terminal
    local selected=0
    local items=(
        "📊 Show Pod Information"
        "🔒 Setup SSH Access"
        "🔑 Show SSH Connection Details"
        "❌ Exit"
    )
    
    while true; do
        # Get terminal size
        local LINES=$(tput lines)
        local COLS=$(tput cols)
        
        # Menu dimensions
        local menu_width=60
        local menu_height=12
        local menu_top=$(( (LINES-menu_height)/2 ))
        local menu_left=$(( (COLS-menu_width)/2 ))
        
        # Clear screen
        clear
        
        # Draw title
        tput cup $menu_top $menu_left
        printf "OhMyRunPod\n"
        
        # Welcome message
        tput cup $((menu_top+1)) $menu_left
        printf "Welcome to your RunPod interface!\n"
        
        # Zero GPU warning if applicable
        if [ "${RUNPOD_GPU_COUNT:-1}" = "0" ]; then
            tput cup $((menu_top+2)) $menu_left
            printf "${YELLOW}⚠️  Running in Zero GPU mode (512MB RAM)${NORMAL}\n"
            tput cup $((menu_top+3)) $menu_left
            printf "${YELLOW}📂 File server running on port 8888${NORMAL}\n"
        fi
        
        # Separator
        tput cup $((menu_top+4)) $menu_left
        printf "──────────────────────\n"
        
        # Menu items
        local current_line=$((menu_top+5))
        for i in "${!items[@]}"; do
            tput cup $current_line $menu_left
            if [ $i -eq $selected ]; then
                printf "${BOLD}${BLUE}▶ %s${NORMAL}\n" "${items[$i]}"
            else
                printf "  %s\n" "${items[$i]}"
            fi
            ((current_line++))
        done
        
        # Navigation help
        tput cup $((current_line+1)) $menu_left
        printf "↑↓ to navigate • Enter to select • q to quit\n"
        
        # Read input
        read -s -n 1 key
        case $key in
            "A") # Up arrow
                ((selected--))
                [ $selected -lt 0 ] && selected=$((${#items[@]}-1))
                ;;
            "B") # Down arrow
                ((selected++))
                [ $selected -ge ${#items[@]} ] && selected=0
                ;;
            "") # Enter
                case $selected in
                    0) get_pod_info ;;
                    1) setup_ssh ;;
                    2) display_connection_info ;;
                    3) exit 0 ;;
                esac
                ;;
            "q") exit 0 ;;
        esac
    done
}

# Start the application
if [ "${RUNPOD_GPU_COUNT:-1}" = "0" ]; then
    handle_zero_gpu
fi
show_menu
