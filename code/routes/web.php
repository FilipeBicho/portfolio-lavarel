<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('frontend.default.home');
});
