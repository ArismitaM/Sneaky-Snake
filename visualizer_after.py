import numpy as np
import matplotlib.pyplot as plt


class SnakeOnChip:

    def __init__(self, ref, query, E, t=8, y=4):

        self.R = ref
        self.Q = query

        self.lenR = len(ref)
        self.lenQ = len(query)

        self.m = max(self.lenR, self.lenQ)

        self.E = E
        self.rows = 2 * E + 1

        # hardware parameters
        self.t = t
        self.y = y


    # ------------------------------------------------------------
    # Build chip maze bitvectors for a given subproblem
    # ------------------------------------------------------------
    def build_chip_maze(self, start):

        bitvectors = []

        for i in range(self.rows):

            shift = i - self.E
            bitvec = 0

            for j in range(self.t):

                col = start + j

                r_index = col
                q_index = col + shift

                if (0 <= r_index < self.lenR and
                    0 <= q_index < self.lenQ and
                    self.R[r_index] == self.Q[q_index]):

                    bit = 0
                else:
                    bit = 1

                bitvec |= (bit << j)

            bitvectors.append(bitvec)

        return bitvectors


    # ------------------------------------------------------------
    # Leading Zero Counter
    # ------------------------------------------------------------
    def leading_zero_count(self, bitvec):

        count = 0

        for j in range(self.t):

            bit = (bitvec >> j) & 1

            if bit == 0:
                count += 1
            else:
                break

        return count


    # ------------------------------------------------------------
    # Comparator tree (max LZC)
    # ------------------------------------------------------------
    def longest_escape(self, bitvectors):

        max_lzc = 0

        for bv in bitvectors:

            lzc = self.leading_zero_count(bv)

            if lzc > max_lzc:
                max_lzc = lzc

        return max_lzc


    # ------------------------------------------------------------
    # Shift bitvectors (checkpoint update)
    # ------------------------------------------------------------
    def shift_bitvectors(self, bitvectors, shift):

        return [bv >> shift for bv in bitvectors]


    # ------------------------------------------------------------
    # Simulate hardware pipeline
    # ------------------------------------------------------------
    def run_pipeline(self, bitvectors):

        xs = []
        current = bitvectors.copy()

        remaining = self.t

        for _ in range(self.y):

            if remaining <= 0:
                break

            x = self.longest_escape(current)
            x = min(x, remaining)

            xs.append(x)

            shift = x

            if shift < remaining:
                shift += 1

            current = self.shift_bitvectors(current, shift)

            remaining -= shift

        return xs


    # ------------------------------------------------------------
    # Run Snake-on-Chip
    # ------------------------------------------------------------
    def run(self, verbose=True):

        total_obstacles = 0

        num_subproblems = (self.m + self.t - 1) // self.t

        for s in range(num_subproblems):

            start = s * self.t

            bitvectors = self.build_chip_maze(start)

            if verbose:
                print(f"\nSubproblem {s}  (columns {start} → {start+self.t-1})")
                self.print_bitvectors(bitvectors)

            xs = self.run_pipeline(bitvectors)

            if verbose:
                print("Escape segments:", xs)

            obstacles = min(self.y, max(0, self.t - sum(xs)))

            if verbose:
                print("Obstacles in subproblem:", obstacles)

            total_obstacles += obstacles

        return total_obstacles


    # ------------------------------------------------------------
    # Utility
    # ------------------------------------------------------------
    def print_bitvectors(self, bitvectors):

        for row in bitvectors:
            bits = format(row, f'0{self.t}b')[::-1]
            print(bits)


# ------------------------------------------------------------
# Visualization class
# ------------------------------------------------------------
class SnakeVisualizer:

    def __init__(self, soc):
        self.soc = soc


    def build_full_maze(self):

        rows = self.soc.rows
        m = self.soc.m

        maze = np.ones((rows, m))

        for i in range(rows):

            shift = i - self.soc.E

            for j in range(m):

                r = j
                q = j + shift

                if (0 <= r < self.soc.lenR and
                    0 <= q < self.soc.lenQ and
                    self.soc.R[r] == self.soc.Q[q]):

                    maze[i, j] = 0

        return maze


    # ------------------------------------------------------------
    # Compute routing path (visual demonstration)
    # ------------------------------------------------------------
    def compute_path(self):

        maze = self.build_full_maze()

        r = self.soc.E
        c = 0

        path = [(r, c)]
        obstacles = []

        while c < self.soc.m:

            best_row = r
            best_len = 0

            for row in range(self.soc.rows):

                length = 0

                while (c + length < self.soc.m and
                       maze[row][c + length] == 0):

                    length += 1

                if length > best_len:
                    best_len = length
                    best_row = row

            for i in range(best_len):
                path.append((best_row, c + i))

            c += best_len

            if c >= self.soc.m:
                break

            obstacles.append((best_row, c))
            path.append((best_row, c))

            c += 1
            r = best_row

        return maze, path, obstacles


    # ------------------------------------------------------------
    # Plot maze + path
    # ------------------------------------------------------------
    def plot_path(self):

        maze, path, obstacles = self.compute_path()

        plt.figure(figsize=(12,4))
        plt.imshow(maze, cmap="gray_r")

        px = [p[1] for p in path]
        py = [p[0] for p in path]

        plt.plot(px, py, color="red", linewidth=2, label="Routing Path")

        ox = [o[1] for o in obstacles]
        oy = [o[0] for o in obstacles]

        plt.scatter(ox, oy, color="blue", s=80, label="Obstacle")

        plt.title("SneakySnake Chip Maze Routing")
        plt.xlabel("Sequence Position")
        plt.ylabel("HRT Row (shift)")

        plt.legend()
        plt.show()

# ------------------------------------------------------------
# Batch Processing from File
# ------------------------------------------------------------
def process_file(input_file, output_file, E=5, t=8, y=4):

    accepted = 0
    rejected = 0
    total = 0

    with open(input_file, 'r') as fin, open(output_file, 'w') as fout:

        for line in fin:
            line = line.strip()

            if not line:
                continue

            # sequences are tab-separated
            parts = line.split('\t')

            if len(parts) != 2:
                continue

            R = parts[0].strip()
            Q = parts[1].strip()

            soc = SnakeOnChip(R, Q, E, t=t, y=y)

            obstacles = soc.run(verbose=False)

            if obstacles <= E:
                result = "ACCEPT"
                accepted += 1
            else:
                result = "REJECT"
                rejected += 1

            fout.write(f"{result}\n")

            total += 1

    # -----------------------------
    # Final Stats
    # -----------------------------
    print("\n===== SUMMARY =====")
    print("Total pairs     :", total)
    print("Accepted pairs  :", accepted)
    print("Rejected pairs  :", rejected)

    if total > 0:
        filtering_rate = rejected / total
        print("Filtering rate  :", filtering_rate)
    else:
        print("Filtering rate  : 0")

if __name__ == "__main__":

    input_file = "input2.txt"
    output_file = "results.txt"

    process_file(input_file, output_file, E=5, t=8, y=4)