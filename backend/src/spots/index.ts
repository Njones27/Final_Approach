import { catalog } from './catalog.ts';
import { makeSpotsHandler } from './handler.ts';

/** The function behind the spot routes. */
export const handler = makeSpotsHandler({ airports: catalog });
