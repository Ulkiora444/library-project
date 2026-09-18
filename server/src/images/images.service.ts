import { Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import * as fs  from 'fs';
import * as path from 'path';

@Injectable()
export class ImagesService {
    constructor(){}

    private getUniqueFilename(filePath: string, extension: string){
        let filename = '';
        do{
            filename = randomUUID() + '.' + extension;
        }while(fs.existsSync(path.join(filePath, filename)));
        return filename;
    }

    private getFileExtension(file, defaultExtension: string){
        const originalExtension = path.extname(file.originalname || '').replace('.', '').toLowerCase();
        if(originalExtension){
            return originalExtension;
        }

        const mimeExtension = (file.mimetype || '').split('/')[1];
        return mimeExtension || defaultExtension;
    }

    async openFile(file, surname, name){
        const filePath = path.resolve(__dirname, '..', '..', '..', 'public', 'images' , `${surname}${name}_`+file);
        // console.log(fs.readFileSync(filePath))
        return fs.readFileSync(filePath);
    }

    saveImage(file){
        try{
            const filePath = path.resolve(__dirname, '..', '..', '..', 'public', 'images');
            if(!fs.existsSync(filePath)){
                fs.mkdirSync(filePath, {recursive: true});
            }
            const extension = this.getFileExtension(file, 'jpg');
            const filename = this.getUniqueFilename(filePath, extension);
            fs.writeFileSync(path.join(filePath, filename), file.buffer);
            return filename;
        }catch(e){
            return ''
        }
    }

    async saveVideo(file){
        try{
            const filePath = path.resolve(__dirname, '..', '..', '..', 'public', 'images');
            if(!fs.existsSync(filePath)){
                fs.mkdirSync(filePath, {recursive: true});
            }
            const filename = this.getUniqueFilename(filePath, 'mp4');
            fs.writeFileSync(path.join(filePath, filename), file.buffer);
            return filename;
        }catch(e){
            return ''
        }
    }

    saveEpub(file){
        try{
            const filePath = path.resolve(__dirname, '..', '..', '..', 'public', 'images');
            if(!fs.existsSync(filePath)){
                fs.mkdirSync(filePath, {recursive: true});
            }
            const filename = this.getUniqueFilename(filePath, 'epub');
            fs.writeFileSync(path.join(filePath, filename), file.buffer);
            return filename;
        }catch(e){
            return ''
        }
    }

    savePdf(file){
        try{
            const filePath = path.resolve(__dirname, '..', '..', '..', 'public', 'images');
            if(!fs.existsSync(filePath)){
                fs.mkdirSync(filePath, {recursive: true});
            }
            const filename = this.getUniqueFilename(filePath, 'pdf');
            fs.writeFileSync(path.join(filePath, filename), file.buffer);
            return filename;
        }catch(e){
            return ''
        }
    }

    // async saveFile(file, surname: string, name: string){
    //     try{
    //         const filename = surname+name+'_'+file.originalname;
    //         const filePath = path.resolve(__dirname, '..', '..', '..', 'public', 'images');
    //         if(!fs.existsSync(filePath)){
    //             fs.mkdirSync(filePath, {recursive: true});
    //         }
    //         fs.writeFileSync(path.join(filePath, filename), file.buffer);
            
    //         let nameSave = filename.slice((surname+name+'_').length);

    //         return nameSave;
    //     }catch(e){
    //         return ''
    //     }
    // }

    async delete(name: string){
        fs.unlinkSync("./public/images/"+name);
    }
}
