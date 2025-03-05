import * as fs from 'fs';

/**
 * Counts the number of lines in the "rows.txt" file by counting line breaks.
 * @param filePath Path to the text file (default: "rows.txt").
 * @returns Promise<number> Number of lines in the file.
 */
async function countLines(filePath: string = 'rows.txt'): Promise<number> {
  try {
    const fileContent = await fs.promises.readFile(filePath, 'utf8');
    return fileContent.split('\n').length;
  } catch (error: unknown) {
    if (error instanceof Error) {
      throw new Error(`Error reading file: ${error.message}`);
    } else {
      throw new Error('Unknown error occurred while reading the file.');
    }
  }
}

export { countLines }
