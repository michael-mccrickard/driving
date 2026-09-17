import re
import random

KEYWORDS = {"up", "down", "flat"}
variables = {}

def format_number(value):
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)

def is_variable_definition(line):
    match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+(?:\.\d+)?)", line.strip())
    if not match:
        return None
    name = match.group(1)
    value = float(match.group(2))
    if value.is_integer(): value = int(value)
    return name, value

def is_variable_operation(line):
    match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(inc|dec)\s*\(\s*(-?\d+(?:\.\d+)?|[A-Za-z_][A-Za-z0-9_]*)\s*\)", line.strip())
    if not match: return None
    return match.group(1), match.group(2), match.group(3)

def replace_variables(line):
    def replacement(match):
        name = match.group(0)
        if name in KEYWORDS: return name
        if name not in variables: raise ValueError(f"Undefined variable: {name}")
        return format_number(variables[name])
    return re.sub(r"[A-Za-z_][A-Za-z0-9_]*", replacement, line)

def replace_random_expressions(line):
    pattern = re.compile(r"\brnd\s*\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)")
    def replacement(match):
        low, high = float(match.group(1)), float(match.group(2))
        if not low.is_integer() or not high.is_integer():
            raise ValueError("rnd() requires integer numeric literals: rnd(low, high)")
        low, high = int(low), int(high)
        if low > high: raise ValueError(f"rnd() low value cannot be greater than high value: rnd({low}, {high})")
        return str(random.randint(low, high))
    return pattern.sub(replacement, line)

def validate_command(line):
    parts = line.split()
    if not parts: return
    if parts[0] not in KEYWORDS: raise ValueError(f"Unknown command: {parts[0]}")
    if len(parts) not in (2, 3): raise ValueError(f"'{parts[0]}' must be followed by one or two numerical values: {line}")
    for value in parts[1:]:
        try: float(value)
        except ValueError: raise ValueError(f"Expected a numerical value after '{parts[0]}': {line}")

def process_variable_operation(line):
    operation = is_variable_operation(line)
    if operation is None: return False
    variable_name, operator, operand = operation
    if variable_name not in variables: raise ValueError(f"Cannot modify undefined variable: {variable_name}")
    try:
        amount = float(operand)
        if amount.is_integer(): amount = int(amount)
    except ValueError:
        if operand not in variables: raise ValueError(f"Undefined variable used as operand: {operand}")
        amount = variables[operand]
    if operator == "inc": variables[variable_name] += amount
    else: variables[variable_name] -= amount
    return True

def find_matching_bracket(lines, start_line, start_position):
    depth = 1
    line_index, position = start_line, start_position
    while line_index < len(lines):
        line = lines[line_index]
        while position < len(line):
            if line[position] == "[": depth += 1
            elif line[position] == "]":
                depth -= 1
                if depth == 0: return line_index, position
            position += 1
        line_index += 1; position = 0
    raise ValueError("Multiplier block has no matching ']'.")

def extract_block(lines, opening_line, opening_position):
    closing_line, closing_position = find_matching_bracket(lines, opening_line, opening_position + 1)
    block_lines = []
    first_part = lines[opening_line][opening_position + 1:]
    if closing_line == opening_line:
        first_part = first_part[:closing_position - opening_position - 1]
        if first_part.strip(): block_lines.append(first_part.strip())
    else:
        if first_part.strip(): block_lines.append(first_part.strip())
        block_lines.extend(lines[opening_line + 1:closing_line])
        last_part = lines[closing_line][:closing_position]
        if last_part.strip(): block_lines.append(last_part.strip())
    return block_lines, closing_line, closing_position

def process_lines(lines, start_index=0, end_index=None):
    if end_index is None: end_index = len(lines)
    output = []; i = start_index
    while i < end_index:
        line = lines[i].strip()
        if not line: i += 1; continue
        assignment = is_variable_definition(line)
        if assignment is not None:
            variables[assignment[0]] = assignment[1]; i += 1; continue
        if process_variable_operation(line): i += 1; continue
        multiplier_match = re.match(r"^(\d+)\s*\[", line)
        if multiplier_match:
            multiplier = int(multiplier_match.group(1)); opening_position = line.find("[")
            block_lines, closing_line, _ = extract_block(lines, i, opening_position)
            expanded_block = []
            for _ in range(multiplier):
                block_output, _ = process_lines(block_lines, 0, len(block_lines))
                expanded_block.extend(block_output)
            output.extend(expanded_block); i = closing_line + 1; continue
        processed = replace_random_expressions(line)
        processed = replace_variables(processed)
        validate_command(processed)
        output.append(processed); i += 1
    return output, i

def process_round(lines):
    global variables
    variables = {}
    result, _ = process_lines(lines)
    print("\n--- FINISHED OUTPUT ---")
    for line in result: print(line)
    print("--- END OUTPUT ---")

def main():
    print("Track Interpolator")
    print("==================\n")
    print("Enter a set of commands, one per line.")
    print("Press Enter on an empty line to process the current set.")
    print("Type 'quit' on a line by itself to exit.\n")
    print("Supported: up, down, flat; variables; x.inc(n), x.dec(n); rnd(low, high); multipliers.\n")
    while True:
        lines = []
        while True:
            try: line = input()
            except EOFError: print(); return
            if line.strip().lower() == "quit": print("Goodbye."); return
            if line == "": break
            lines.append(line)
        if not lines: print("Goodbye."); return
        try: process_round(lines)
        except ValueError as error: print(f"\nERROR: {error}")
        print("\nEnter another set of commands, or type 'quit' to exit.\n")

if __name__ == "__main__": main()
