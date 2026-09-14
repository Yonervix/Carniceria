import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { AvisoComponent } from './core/componentes/aviso.component';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, AvisoComponent],
  styleUrl: './app.css',
  template: '<router-outlet />\n<app-aviso />',
})
export class App {}