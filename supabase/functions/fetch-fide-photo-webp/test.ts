import { Image } from "https://deno.land/x/imagescript@1.3.0/mod.ts";
const i = new Image(10, 10);
console.log(Object.getOwnPropertyNames(Object.getPrototypeOf(i)));
