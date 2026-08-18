<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\DutyController;
use App\Http\Controllers\ManifestController;

Route::get('/health', [DutyController::class, 'health']);
Route::post('/duty/calculate', [DutyController::class, 'calculate']);
Route::get('/manifest/{manifestRef}', [ManifestController::class, 'lookup']);
