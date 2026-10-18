import {mkdirSync,copyFileSync} from 'node:fs';
mkdirSync('public/data',{recursive:true});
copyFileSync('data/reservations.json','public/data/reservations.json');
